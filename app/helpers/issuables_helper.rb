module IssuablesHelper
  def sidebar_gutter_toggle_icon
    sidebar_gutter_collapsed? ? icon('angle-double-left') : icon('angle-double-right')
  end

  def sidebar_gutter_collapsed_class
    "right-sidebar-#{sidebar_gutter_collapsed? ? 'collapsed' : 'expanded'}"
  end

  def multi_label_name(current_labels, default_label)
    if current_labels && current_labels.any?
      title = current_labels.first.try(:title)
      if current_labels.size > 1
        "超前 #{title} +#{current_labels.size - 1}"
      else
        title
      end
    else
      default_label
    end
  end

  def issuable_json_path(issuable)
    project = issuable.project

    if issuable.kind_of?(MergeRequest)
      namespace_project_merge_request_path(project.namespace, project, issuable.iid, :json)
    else
      namespace_project_issue_path(project.namespace, project, issuable.iid, :json)
    end
  end

  def template_dropdown_tag(issuable, &block)
    title = selected_template(issuable) || "Choose a template"
    options = {
      toggle_class: 'js-issuable-selector',
      title: title,
      filter: true,
      placeholder: 'Filter',
      footer_content: true,
      data: {
        data: issuable_templates(issuable),
        field_name: 'issuable_template',
        selected: selected_template(issuable),
        project_path: ref_project.path,
        namespace_path: ref_project.namespace.path
      }
    }

    dropdown_tag(title, options: options) do
      capture(&block)
    end
  end

  def user_dropdown_label(user_id, default_label)
    return default_label if user_id.nil?
    return "未指派" if user_id == "0"

    user = User.find_by(id: user_id)

    if user
      user.name
    else
      default_label
    end
  end

  def project_dropdown_label(project_id, default_label)
    return default_label if project_id.nil?
    return "Any project" if project_id == "0"

    project = Project.find_by(id: project_id)

    if project
      project.name_with_namespace
    else
      default_label
    end
  end

  def milestone_dropdown_label(milestone_title, default_label = "里程碑")
    if milestone_title == Milestone::Upcoming.name
      milestone_title = Milestone::Upcoming.title
    end

    h(milestone_title.presence || default_label)
  end

  def issuable_meta(issuable, project, text)
    output = content_tag :strong, "#{text} #{issuable.to_reference}", class: "identifier"
    output << " 在 #{time_ago_with_tooltip(issuable.created_at)} 由 ".html_safe
    output << content_tag(:strong) do
      author_output = link_to_member(project, issuable.author, size: 24, mobile_classes: "hidden-xs", tooltip: true)
      author_output << link_to_member(project, issuable.author, size: 24, by_username: true, avatar: false, mobile_classes: "hidden-sm hidden-md hidden-lg")
    end

    if issuable.tasks?
      output << "&ensp;".html_safe
      output << content_tag(:span, issuable.task_status, id: "task_status", class: "hidden-xs")
      output << content_tag(:span, issuable.task_status_short, id: "task_status_short", class: "hidden-sm hidden-md hidden-lg")
    end

    output
  end

  def issuable_todo(issuable)
    if current_user
      current_user.todos.find_by(target: issuable, state: :pending)
    end
  end

  def issuable_labels_tooltip(labels, limit: 5)
    first, last = labels.partition.with_index{ |_, i| i < limit  }

    label_names = first.collect(&:name)
    label_names << "and #{last.size} more" unless last.empty?

    label_names.join(', ')
  end

  def issuables_state_counter_text(issuable_type, state)
    titles = {
      opened: "未关闭",
      closed: "已关闭",
      merged: "已合并",
      all: "所有"
    }

    state_title = titles[state] || state.to_s.humanize

    count =
      Rails.cache.fetch(issuables_state_counter_cache_key(issuable_type, state), expires_in: 2.minutes) do
        issuables_count_for_state(issuable_type, state)
      end

    html = content_tag(:span, state_title)
    html << " " << content_tag(:span, number_with_delimiter(count), class: 'badge')

    html.html_safe
  end

  def cached_assigned_issuables_count(assignee, issuable_type, state)
    cache_key = hexdigest(['assigned_issuables_count', assignee.id, issuable_type, state].join('-'))
    Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      assigned_issuables_count(assignee, issuable_type, state)
    end
  end

  private

  def assigned_issuables_count(assignee, issuable_type, state)
    assignee.public_send("assigned_#{issuable_type}").public_send(state).count
  end

  def sidebar_gutter_collapsed?
    cookies[:collapsed_gutter] == 'true'
  end

  def base_issuable_scope(issuable)
    issuable.project.send(issuable.class.table_name).send(issuable_state_scope(issuable))
  end

  def issuable_state_scope(issuable)
    if issuable.respond_to?(:merged?) && issuable.merged?
      :merged
    else
      issuable.open? ? :opened : :closed
    end
  end

  def issuable_filters_present
    params[:search] || params[:author_id] || params[:assignee_id] || params[:milestone_title] || params[:label_name]
  end

  def issuables_count_for_state(issuable_type, state)
    issuables_finder = public_send("#{issuable_type}_finder")
    
    params = issuables_finder.params.merge(state: state)
    finder = issuables_finder.class.new(issuables_finder.current_user, params)

    finder.execute.page(1).total_count
  end

  IRRELEVANT_PARAMS_FOR_CACHE_KEY = %i[utf8 sort page]
  private_constant :IRRELEVANT_PARAMS_FOR_CACHE_KEY

  def issuables_state_counter_cache_key(issuable_type, state)
    opts = params.with_indifferent_access
    opts[:state] = state
    opts.except!(*IRRELEVANT_PARAMS_FOR_CACHE_KEY)

    hexdigest(['issuables_count', issuable_type, opts.sort].flatten.join('-'))
  end

  def issuable_templates(issuable)
    @issuable_templates ||=
      case issuable
      when Issue
        issue_template_names
      when MergeRequest
        merge_request_template_names
      else
        raise '未知的问题类型!'
      end
  end

  def merge_request_template_names
    @merge_request_templates ||= Gitlab::Template::MergeRequestTemplate.dropdown_names(ref_project)
  end

  def issue_template_names
    @issue_templates ||= Gitlab::Template::IssueTemplate.dropdown_names(ref_project)
  end

  def selected_template(issuable)
    params[:issuable_template] if issuable_templates(issuable).include?(params[:issuable_template])
  end
end

module TodosHelper
  def todos_pending_count
    @todos_pending_count ||= current_user.todos_pending_count
  end

  def todos_done_count
    @todos_done_count ||= current_user.todos_done_count
  end

  def todo_action_name(todo)
    case todo.action
    when Todo::ASSIGNED then '给您指派了'
    when Todo::MENTIONED then '向您提及了'
    when Todo::BUILD_FAILED then '你的构建失败了'
    when Todo::MARKED then '向您标记了'
    when Todo::APPROVAL_REQUIRED then '请您审批'
    end
  end

  def todo_target_link(todo)
    target = todo.target_type_zh
    link_to "#{target} #{todo.target_reference}", todo_target_path(todo),
      class: 'has-tooltip',
      title: todo.target.title
  end

  def todo_target_path(todo)
    return unless todo.target.present?

    anchor = dom_id(todo.note) if todo.note.present?

    if todo.for_commit?
      namespace_project_commit_path(todo.project.namespace.becomes(Namespace), todo.project,
                                    todo.target, anchor: anchor)
    else
      path = [todo.project.namespace.becomes(Namespace), todo.project, todo.target]

      path.unshift(:builds) if todo.build_failed?

      polymorphic_path(path, anchor: anchor)
    end
  end

  def todo_target_state_pill(todo)
    return unless show_todo_state?(todo)

    content_tag(:span, nil, class: 'target-status') do
      content_tag(:span, nil, class: "status-box status-box-#{todo.target.state.dasherize}") do
        todo.target.state.capitalize
      end
    end
  end

  def todos_filter_params
    {
      state:      params[:state],
      project_id: params[:project_id],
      author_id:  params[:author_id],
      type:       params[:type],
      action_id:  params[:action_id],
    }
  end

  def todos_filter_empty?
    todos_filter_params.values.none?
  end

  def todos_filter_path(options = {})
    without = options.delete(:without)

    options = todos_filter_params.merge(options)

    if without.present?
      without.each do |key|
        options.delete(key)
      end
    end

    path = request.path
    path << "?#{options.to_param}"
    path
  end

  def todo_actions_options
    [
      { id: '', text: '任何动作' },
      { id: Todo::ASSIGNED, text: '被指派' },
      { id: Todo::MENTIONED, text: '被提及' }
    ]
  end

  def todo_projects_options
    projects = current_user.authorized_projects.sorted_by_activity.non_archived
    projects = projects.includes(:namespace)

    projects = projects.map do |project|
      { id: project.id, text: project.name_with_namespace }
    end

    projects.unshift({ id: '', text: '任何项目' }).to_json
  end

  def todo_types_options
    [
      { id: '', text: '任何类型' },
      { id: 'Issue', text: '问题' },
      { id: 'MergeRequest', text: '合并请求' }
    ]
  end

  def todo_actions_dropdown_label(selected_action_id, default_action)
    selected_action = todo_actions_options.find { |action| action[:id] == selected_action_id.to_i}
    selected_action ? selected_action[:text] : default_action
  end

  def todo_types_dropdown_label(selected_type, default_type)
    selected_type = todo_types_options.find { |type| type[:id] == selected_type && type[:id] != '' }
    selected_type ? selected_type[:text] : default_type
  end

  def todo_due_date(todo)
    return unless todo.target.try(:due_date)

    is_due_today = todo.target.due_date.today?
    is_overdue = todo.target.overdue?
    css_class =
      if is_due_today
        'text-warning'
      elsif is_overdue
        'text-danger'
      else
        ''
      end

    html = "&middot; ".html_safe
    html << content_tag(:span, class: css_class) do
      "截止日期 #{is_due_today ? "今天" : todo.target.due_date.to_s(:medium)}"
    end
  end

  private

  def show_todo_state?(todo)
    (todo.target.is_a?(MergeRequest) || todo.target.is_a?(Issue)) && ['closed', 'merged'].include?(todo.target.state)
  end
end

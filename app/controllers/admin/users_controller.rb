class Admin::UsersController < Admin::ApplicationController
  before_action :user, except: [:index, :new, :create]

  def index
    @users = User.order_name_asc.filter(params[:filter])
    @users = @users.search_with_secondary_emails(params[:search_query]) if params[:search_query].present?
    @users = @users.sort(@sort = params[:sort])
    @users = @users.page(params[:page])
  end

  def show
  end

  def projects
    @personal_projects = user.personal_projects
    @joined_projects = user.projects.joined(@user)
  end

  def groups
  end

  def keys
    @keys = user.keys
  end

  def new
    @user = User.new
  end

  def edit
    user
  end

  def impersonate
    if user.blocked?
      flash[:alert] = "你不能扮演被禁用的用户"

      redirect_to admin_user_path(user)
    else
      session[:impersonator_id] = current_user.id

      warden.set_user(user, scope: :user)

      Gitlab::AppLogger.info("User #{current_user.username} has started impersonating #{user.username}")

      flash[:alert] = "你正在扮演 #{user.username}"

      redirect_to root_path
    end
  end

  def block
    if user.block
      redirect_back_or_admin_user(notice: "禁用成功")
    else
      redirect_back_or_admin_user(alert: "发生错误。用户未被禁止")
    end
  end

  def unblock
    if user.ldap_blocked?
      redirect_back_or_admin_user(alert: "此用户无法通过 GitLab 来启用")
    elsif user.activate
      redirect_back_or_admin_user(notice: "启用成功")
    else
      redirect_back_or_admin_user(alert: "发生错误。用户未被启用")
    end
  end

  def unlock
    if user.unlock_access!
      redirect_back_or_admin_user(alert: "解除锁定成功")
    else
      redirect_back_or_admin_user(alert: "发生错误。用户未被解除锁定")
    end
  end

  def confirm
    if user.confirm
      redirect_back_or_admin_user(notice: "确认成功")
    else
      redirect_back_or_admin_user(alert: "发生错误。用户未被确认")
    end
  end

  def disable_two_factor
    user.disable_two_factor!
    redirect_to admin_user_path(user),
      notice: '此用户已禁止两步验证'
  end

  def create
    opts = {
      force_random_password: true,
      password_expires_at: nil
    }

    @user = User.new(user_params.merge(opts))
    @user.created_by_id = current_user.id
    @user.generate_password
    @user.generate_reset_token
    @user.skip_confirmation!

    respond_to do |format|
      if @user.save
        format.html { redirect_to [:admin, @user], notice: '用户创建成功。' }
        format.json { render json: @user, status: :created, location: @user }
      else
        format.html { render "new" }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    user_params_with_pass = user_params.dup

    if params[:user][:password].present?
      user_params_with_pass.merge!(
        password: params[:user][:password],
        password_confirmation: params[:user][:password_confirmation],
        password_expires_at: Time.now
      )
    end

    respond_to do |format|
      user.skip_reconfirmation!
      if user.update_attributes(user_params_with_pass)
        format.html { redirect_to [:admin, user], notice: '用户更新成功。' }
        format.json { head :ok }
      else
        # restore username to keep form action url.
        user.username = params[:id]
        format.html { render "edit" }
        format.json { render json: user.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    DeleteUserWorker.perform_async(current_user.id, user.id)

    respond_to do |format|
      format.html { redirect_to admin_users_path, notice: "用户删除成功。" }
      format.json { head :ok }
    end
  end

  def remove_email
    email = user.emails.find(params[:email_id])
    email.destroy

    user.update_secondary_emails!

    respond_to do |format|
      format.html { redirect_back_or_admin_user(notice: "删除邮箱成功。") }
      format.js { head :ok }
    end
  end

  protected

  def user
    @user ||= User.find_by!(username: params[:id])
  end

  def user_params
    params.require(:user).permit(
      :email, :remember_me, :bio, :name, :username,
      :skype, :linkedin, :twitter, :website_url, :color_scheme_id, :theme_id, :force_random_password,
      :extern_uid, :provider, :password_expires_at, :avatar, :hide_no_ssh_key, :hide_no_password,
      :projects_limit, :can_create_group, :admin, :key_id, :external
    )
  end

  def redirect_back_or_admin_user(options = {})
    redirect_back_or_default(default: default_route, options: options)
  end

  def default_route
    [:admin, @user]
  end
end

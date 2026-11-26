# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class Users::RegistrationsController < Devise::RegistrationsController
  layout -> { Components::Layout }
  # Devise 컨트롤러 안의 authenticate_user!는 force 없이 아무것도 하지 않는다. 대신 Devise의 authenticate_scope!
  # (force 인증 + resource 설정)를 password에도 건다. 같은 콜백을 다시 선언하면 Devise의 only 목록을 덮으므로 모두 적는다.
  prepend_before_action :authenticate_scope!, only: %i[edit password update destroy]

  def new
    build_resource
    render Views::Users::New.new(user: resource)
  end

  def create
    build_resource(sign_up_params)
    resource.signup_host = safe_signup_host
    resource.locale ||= I18n.locale.to_s

    resource.save
    if resource.persisted?
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    else
      clean_up_passwords resource
      render Views::Users::New.new(user: resource), status: :unprocessable_entity
    end
  end

  # JSON(현재 사용자 조회)은 Api::V1::AccountController#show로 이관했다.
  def edit
    render Views::Users::Edit.new(user: resource)
  end

  def password
    render Views::Users::Password.new(user: resource)
  end

  def update
    if updating_password?
      update_user_password
    else
      update_without_password
    end
  end

  def destroy
    resource.destroy!
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    redirect_to root_path, status: :see_other, notice: "계정이 삭제되었습니다."
  end

  protected

  def after_sign_up_path_for(_resource)
    root_path
  end

  def after_inactive_sign_up_path_for(_resource)
    root_path
  end

  def sign_up_params
    params.expect(user: [ :email, :name, :username, :password, :password_confirmation, :locale ])
  end

  def account_update_params
    params.expect(user: [ :email, :name, :avatar, :remove_avatar, :locale ])
  end

  private

  def safe_signup_host
    host = request.host.to_s.downcase
    User::SUPPORTED_SIGNUP_HOSTS.include?(host) ? host : User::SUPPORTED_SIGNUP_HOSTS.first
  end

  def updating_password?
    user = params[:user]
    return false unless user.respond_to?(:key?)
    user.key?(:password) || user.key?(:password_confirmation)
  end

  def update_user_password
    password_params = params.expect(user: [ :current_password, :password, :password_confirmation ])
    if resource.update_with_password(password_params)
      bypass_sign_in resource
      redirect_to edit_user_registration_path, notice: t("devise.registrations.updated")
    else
      render Views::Users::Password.new(user: resource), status: :unprocessable_entity
    end
  end

  def update_without_password
    if update_account_with_avatar
      flash_key = if resource.pending_reconfirmation?
        "devise.registrations.update_needs_confirmation"
      else
        "devise.registrations.updated"
      end
      redirect_to edit_user_registration_path, notice: t(flash_key)
    else
      render Views::Users::Edit.new(user: resource), status: :unprocessable_entity
    end
  end

  def update_account_with_avatar
    permitted_params = account_update_params
    attributes = permitted_params.except(:avatar, :remove_avatar)
    avatar = permitted_params[:avatar]
    remove_avatar = ActiveModel::Type::Boolean.new.cast(permitted_params[:remove_avatar])

    resource.assign_attributes(attributes)

    User.transaction do
      resource.remove_avatar! if remove_avatar
      resource.avatar.attach(avatar) if avatar.present?
      raise ActiveRecord::Rollback unless resource.save
    end

    resource.errors.empty?
  end
end

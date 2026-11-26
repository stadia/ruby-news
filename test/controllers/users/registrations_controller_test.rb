# frozen_string_literal: true

require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:john)
    @avatar_path = Rails.root.join("public/apple-touch-icon.png")
  end

  test "GET edit renders account edit page" do
    sign_in_as(@user)

    get edit_user_registration_path

    assert_response :success
  end

  test "GET new renders sign up page" do
    get new_user_registration_path

    assert_response :success
    assert_select "h2", text: "회원 가입"
    assert_select "input[name='user[username]']"
    assert_select "input[name='user[email]']"
  end

  test "POST create with invalid params rerenders sign up page" do
    post user_registration_path, params: {
      user: {
        email: "",
        username: "",
        password: "",
        password_confirmation: ""
      }
    }

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
  end

  test "PATCH update로 프로필 이미지를 업로드할 수 있다" do
    sign_in_as(@user)

    patch user_registration_path, params: {
      user: {
        email: @user.email,
        name: @user.name,
        avatar: fixture_upload("first-avatar.png")
      }
    }

    assert_redirected_to edit_user_registration_path
    @user.reload

    assert_predicate @user.avatar, :attached?
  end

  test "PATCH update로 프로필 이미지를 교체할 수 있다" do
    sign_in_as(@user)
    @user.avatar.attach(io: File.open(@avatar_path), filename: "old-avatar.png", content_type: "image/png")
    old_blob_id = @user.avatar.blob_id

    patch user_registration_path, params: {
      user: {
        email: @user.email,
        name: @user.name,
        avatar: fixture_upload("replacement-avatar.png")
      }
    }

    assert_redirected_to edit_user_registration_path
    @user.reload

    assert_predicate @user.avatar, :attached?
    assert_not_equal old_blob_id, @user.avatar.blob_id
  end

  test "PATCH update로 프로필 이미지를 제거할 수 있다" do
    sign_in_as(@user)
    @user.avatar.attach(io: File.open(@avatar_path), filename: "old-avatar.png", content_type: "image/png")

    patch user_registration_path, params: {
      user: {
        email: @user.email,
        name: @user.name,
        remove_avatar: "1"
      }
    }

    assert_redirected_to edit_user_registration_path
    @user.reload

    assert_not @user.avatar.attached?
  end

  test "GET password renders password form" do
    sign_in_as(@user)

    get account_password_path

    assert_response :success
    assert_select "form"
    assert_select "input[name='user[current_password]']"
    assert_select "input[name='user[password]']"
  end

  test "GET password without session redirects to login" do
    get account_password_path

    assert_redirected_to new_user_session_path
  end

  test "PATCH update with invalid profile params rerenders edit page" do
    sign_in_as(@user)

    patch user_registration_path, params: {
      user: {
        email: "",
        name: @user.name
      }
    }

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
  end

  test "PATCH update with invalid password params rerenders password page" do
    sign_in_as(@user)

    patch user_registration_path, params: {
      user: {
        current_password: "wrong-password",
        password: "new-password-123",
        password_confirmation: "new-password-123"
      }
    }

    assert_response :unprocessable_entity
    assert_select "input[name='user[current_password]']"
  end

  test "DELETE destroy deletes account and redirects to root" do
    sign_in_as(@user)

    assert_difference("User.count", -1) do
      delete user_registration_path
    end

    assert_redirected_to root_path
  end

  test "GET fedipub server actor는 프로필 icon url을 노출한다" do
    @user.avatar.attach(io: File.open(@avatar_path), filename: "avatar.png", content_type: "image/png")

    get fedipub.server_actor_path(@user.fedipub_actor), headers: { "Accept" => "application/activity+json" }

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "Image", json.dig("icon", "type")
    assert_match %r{\Ahttp://example\.com/rails/active_storage/disk/}, json.dig("icon", "url")
  end

  private

  def fixture_upload(filename)
    Rack::Test::UploadedFile.new(@avatar_path, "image/png", original_filename: filename)
  end
end

# frozen_string_literal: true

require "test_helper"

class Madmin::PreferencesControllerTest < ActionDispatch::IntegrationTest
  test "admin can create OAuth preference with dynamic attributes" do
    sign_in_as users(:admin)

    assert_difference -> { Preference.count }, 1 do
      post madmin_preferences_path, params: {
        preference: {
          name: "_madmin_create_oauth",
          client_id: "madmin-client-id",
          client_secret: "madmin-client-secret"
        }
      }
    end

    preference = Preference.find_by!(name: "_madmin_create_oauth")

    assert_redirected_to madmin_preference_path(preference)
    assert_equal "madmin-client-id", preference.client_id
    assert_equal "madmin-client-secret", preference.client_secret
  end

  test "admin can create host preferences without unrelated OAuth attributes" do
    sign_in_as users(:admin)
    preferences(:ignore_hosts).destroy!

    post madmin_preferences_path, params: {
      preference: { name: "ignore_hosts", hosts: "example.com ruby-lang.org", client_id: "unused" }
    }

    preference = Preference.find_by!(name: "ignore_hosts")

    assert_redirected_to madmin_preference_path(preference)
    assert_equal %w[example.com ruby-lang.org], preference.value
  end

  test "admin can change a preference name and save its new dynamic attributes" do
    sign_in_as users(:admin)
    preference = preferences(:ignore_hosts)

    patch madmin_preference_path(preference), params: {
      preference: { name: "_madmin_renamed_oauth", client_id: "renamed-client", client_secret: "renamed-secret" }
    }

    assert_redirected_to madmin_preference_path(preference)
    assert_equal "renamed-client", preference.reload.value["client_id"]
    assert_equal "renamed-secret", preference.value["client_secret"]
  end

  test "admin can update OAuth dynamic attributes without submitting the name" do
    sign_in_as users(:admin)
    preference = Preference.create!(name: "_madmin_update_oauth", value: { "client_id" => "old-client" })

    patch madmin_preference_path(preference), params: { preference: { client_id: "updated-client" } }

    assert_redirected_to madmin_preference_path(preference)
    assert_equal "updated-client", preference.reload.client_id
  end
end

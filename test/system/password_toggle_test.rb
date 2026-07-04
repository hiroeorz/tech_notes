require "application_system_test_case"

class PasswordToggleTest < ApplicationSystemTestCase
  test "admin login password visibility button toggles the field and accessible state" do
    visit admin_login_path

    password = find("input[name='password']", visible: :all)
    toggle = find("[data-password-toggle]")

    assert_equal "password", password[:type]
    assert_equal "false", toggle["aria-pressed"]
    assert_equal "パスワードを表示する", toggle["aria-label"]

    toggle.click
    assert_equal "text", password[:type]
    assert_equal "true", toggle["aria-pressed"]
    assert_equal "パスワードを非表示にする", toggle["aria-label"]

    toggle.click
    assert_equal "password", password[:type]
    assert_equal "false", toggle["aria-pressed"]
    assert_equal "パスワードを表示する", toggle["aria-label"]
  end
end

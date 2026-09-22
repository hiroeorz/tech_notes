# typed: true

require "test_helper"
require "rake"

class OauthClientTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  test "create issues a confidential client and prints uid and secret" do
    out, _err = capture_io do
      invoke_task("oauth:client:create", "Gemini", "https://client.example.com/callback")
    end

    app = Doorkeeper::Application.find_by(name: "Gemini")
    assert app
    assert app.confidential?
    assert_includes out, "uid: #{app.uid}"
    assert_includes out, "secret: #{app.secret}"
  end

  test "create aborts when the name already exists" do
    Doorkeeper::Application.create!(
      name: "Gemini", redirect_uri: "https://client.example.com/callback",
      scopes: "read write", confidential: true
    )

    assert_raises(SystemExit) do
      capture_io { invoke_task("oauth:client:create", "Gemini", "https://client.example.com/callback") }
    end
    assert_equal 1, Doorkeeper::Application.where(name: "Gemini").count
  end

  test "create aborts without arguments" do
    assert_raises(SystemExit) do
      capture_io { invoke_task("oauth:client:create") }
    end
  end

  test "show prints uid and secret of an existing client" do
    app = Doorkeeper::Application.create!(
      name: "Gemini", redirect_uri: "https://client.example.com/callback",
      scopes: "read write", confidential: true
    )

    out, _err = capture_io { invoke_task("oauth:client:show", "Gemini") }

    assert_includes out, "uid: #{app.uid}"
    assert_includes out, "secret: #{app.secret}"
  end

  test "show aborts for an unknown client" do
    assert_raises(SystemExit) do
      capture_io { invoke_task("oauth:client:show", "Unknown") }
    end
  end

  private

  def invoke_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end
end

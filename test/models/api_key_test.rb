require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
  end

  test "issue returns record and plaintext token without storing the plaintext" do
    key, token = ApiKey.issue(admin_user: @admin, name: "MCP", scope: :read)

    assert_instance_of ApiKey, key
    assert key.persisted?
    assert token.start_with?("tn_")
    assert_operator token.length, :>=, 32
    assert_equal "read", key.scope
    assert_equal "tn_", token[0, 3]
    assert_equal token[0, 8], key.key_prefix
    assert_equal Digest::SHA256.hexdigest(token), key.key_digest
    assert_not_equal token, key.key_digest
    assert_not ApiKey.exists?(key_digest: token)
  end

  test "find_active_by_token returns record for issued token and nil otherwise" do
    key, token = ApiKey.issue(admin_user: @admin, name: "MCP", scope: :write)

    assert_equal key, ApiKey.find_active_by_token(token)
    assert_nil ApiKey.find_active_by_token("wrong-token")
    assert_nil ApiKey.find_active_by_token("")
    assert_nil ApiKey.find_active_by_token(nil)
  end

  test "revoke! marks key inactive and is idempotent" do
    key, token = ApiKey.issue(admin_user: @admin, name: "MCP", scope: :read)

    key.revoke!
    assert_not key.active?
    assert_not_nil key.revoked_at
    assert_nil ApiKey.find_active_by_token(token)

    revoked_at = key.reload.revoked_at
    key.revoke!
    assert_equal revoked_at, key.reload.revoked_at
  end

  test "record_usage! updates last_used_at" do
    key, = ApiKey.issue(admin_user: @admin, name: "MCP", scope: :read)

    assert_nil key.last_used_at
    key.record_usage!
    assert_not_nil key.last_used_at
  end

  test "scope enum provides read and write predicates" do
    read_key, = ApiKey.issue(admin_user: @admin, name: "Read key", scope: :read)
    assert read_key.read?
    assert_not read_key.write?

    write_key, = ApiKey.issue(admin_user: @admin, name: "Write key", scope: :write)
    assert write_key.write?
    assert_not write_key.read?
  end

  test "admin user who owns api keys cannot be deleted" do
    ApiKey.issue(admin_user: @admin, name: "MCP", scope: :read)

    assert_raises(ActiveRecord::DeleteRestrictionError) do
      @admin.destroy!
    end
  end

  test "name is stripped and limited to 100 characters" do
    key, _token = ApiKey.issue(admin_user: @admin, name: "  padded name  ", scope: :read)

    assert_equal "padded name", key.name

    long_key = ApiKey.new(
      admin_user: @admin,
      name: "a" * 101,
      scope: :read,
      key_digest: Digest::SHA256.hexdigest("unique-digest-101"),
      key_prefix: "tn_unique"
    )

    assert_not long_key.valid?
    assert long_key.errors[:name].any?
  end

  test "key_digest must be unique" do
    key, _token = ApiKey.issue(admin_user: @admin, name: "First", scope: :read)

    duplicate = ApiKey.new(
      admin_user: @admin,
      name: "Second",
      scope: :read,
      key_digest: key.key_digest,
      key_prefix: key.key_prefix
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:key_digest].any?
  end
end

require "test_helper"

class BlogFlowTest < ActionDispatch::IntegrationTest
  setup do
    @setting = SiteSetting.current
    @admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @category = Category.create!(name: "AWS", slug: "aws", icon_key: "aws", position: 1)
    @tag = Tag.create!(name: "Terraform", slug: "terraform")
    @post = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "Terraformのリモートステート設計",
      slug: "terraform-remote-state",
      excerpt: "Terraformのリモートステートを設計するためのメモです。",
      body: "## 構成例\n- S3\n- DynamoDB\n```hcl\nterraform {}\n```",
      status: :published,
      kind: :article,
      published_at: Time.current
    )
    @post.tags << @tag
  end

  test "public pages render blog content" do
    get root_path
    assert_response :success
    assert_includes response.body, "Hiroe Tech Notes"
    assert_includes response.body, "考えたことを"

    get posts_path
    assert_response :success
    assert_includes response.body, @post.title

    get post_path(@post.slug)
    assert_response :success
    assert_includes response.body, "Terraform"
    assert_includes response.body, "code-block"
    assert_includes response.body, "https://x.com/intent/tweet"
    assert_includes response.body, feed_path(format: :xml)

    get tags_path
    assert_response :success
    assert_includes response.body, @tag.name

    get categories_path
    assert_response :success
    assert_includes response.body, @category.name
    assert_select "a[href='#{posts_path(category: @category.slug)}'] strong", text: "1"

    get archives_path
    assert_response :success
    assert_includes response.body, "アーカイブ"
    assert_includes response.body, @post.title
  end

  test "post filters tolerate invalid month and experiment search stays on experiments path" do
    get posts_path(month: "not-a-month")
    assert_response :success
    assert_includes response.body, @post.title

    experiment = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "実験ログ検索対象",
      slug: "experiment-search-target",
      excerpt: "実験ログです。",
      body: "## 実験",
      status: :published,
      kind: :experiment,
      published_at: Time.current
    )

    get experiments_path(q: "実験ログ検索対象")
    assert_response :success
    assert_includes response.body, experiment.title
    assert_select "form[action='#{experiments_path}']"
  end

  test "public sidebar tag list and category list count only published posts" do
    draft_category = Category.create!(name: "DraftCategory", slug: "draft-category", icon_key: "code", position: 2)
    draft_tag = Tag.create!(name: "DraftOnly", slug: "draft-only")
    draft = Post.create!(
      admin_user: @admin,
      category: draft_category,
      title: "下書き記事",
      slug: "draft-post",
      excerpt: "下書き記事です。",
      body: "## 下書き",
      status: :draft,
      kind: :article
    )
    draft.tags << draft_tag

    get root_path
    assert_response :success
    assert_select "a[href='#{posts_path(category: @category.slug)}'] strong", text: "1"

    get tags_path
    assert_response :success
    assert_includes response.body, @tag.name
    assert_not_includes response.body, draft_tag.name

    get categories_path
    assert_response :success
    assert_includes response.body, @category.name
    assert_not_includes response.body, draft_category.name
  end

  test "admin can sign in and view management pages" do
    get admin_posts_path
    assert_redirected_to admin_login_path

    get admin_login_path
    assert_response :success
    assert_includes response.body, "ログイン"
    assert_includes response.body, "aria-label=\"パスワードの表示切り替え\""

    post admin_login_path, params: { email: "", password: "" }
    assert_response :unprocessable_entity
    assert_includes response.body, "メールアドレスを入力してください。"
    assert_includes response.body, "パスワードを入力してください。"

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    follow_redirect!
    assert_response :success
    assert_includes response.body, "記事一覧"

    get edit_admin_post_path(@post.slug)
    assert_response :success
    assert_includes response.body, "Markdown"
    assert_includes response.body, "公開予約"
    assert_includes response.body, "name=\"post[status]\" value=\"draft\""
    assert_includes response.body, "name=\"post[status]\" value=\"published\""
    assert_includes response.body, "公開日時"
    assert_includes response.body, "data-md-action=\"bold\""
    assert_includes response.body, "aria-label=\"太字を挿入\""
    assert_includes response.body, "aria-label=\"画像を挿入\""
    assert_includes response.body, "data-tag-input=\"true\""
    assert_select ".tag-preview .chip", text: @tag.name
    assert_includes response.body, "data-live-count-input=\"title\""
    assert_includes response.body, "data-body-stat=\"lines\""

    get preview_admin_post_path(@post.slug)
    assert_response :success
    assert_includes response.body, @post.title

    get admin_settings_path
    assert_response :success
    assert_includes response.body, "管理設定"
    assert_includes response.body, "data-password-toggle"
    assert_includes response.body, "aria-label=\"現在のパスワードの表示切り替え\""
    assert_select "input#site_setting_ogp_image[type='file']"
    assert_select "label[for='site_setting_ogp_image']", text: "画像を変更"
    assert_select "input#site_setting_profile_image[type='file']"
    assert_select "label[for='site_setting_profile_image']", text: "プロフィール画像を変更"
  end

  test "remember me keeps admin signed in through signed cookie and logout clears it" do
    post admin_login_path, params: { email: @admin.email, password: "password123", remember_me: "1" }
    assert_redirected_to admin_posts_path
    assert cookies[:admin_user_id].present?

    remembered_cookie = cookies[:admin_user_id]
    reset!
    cookies[:admin_user_id] = remembered_cookie
    get admin_posts_path
    assert_response :success

    delete admin_logout_path
    assert_redirected_to root_path
    assert cookies[:admin_user_id].blank?
  end

  test "admin can update a post through slug based route" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    patch admin_post_path(@post), params: {
      post: {
        title: "更新したTerraform記事",
        slug: @post.slug,
        excerpt: @post.excerpt,
        body: @post.body,
        category_id: @category.id,
        status: "published",
        kind: "article",
        tag_names: "Terraform, AWS"
      }
    }

    assert_redirected_to edit_admin_post_path(@post.slug)
    assert_equal "更新したTerraform記事", @post.reload.title
  end

  test "admin post list can sort by oldest update" do
    older = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "古い記事",
      slug: "old-post",
      excerpt: "古い記事です。",
      body: "## 古い記事",
      status: :published,
      kind: :article,
      published_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    newer = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "新しい記事",
      slug: "new-post",
      excerpt: "新しい記事です。",
      body: "## 新しい記事",
      status: :published,
      kind: :article,
      published_at: 1.day.ago,
      updated_at: 1.day.ago
    )

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    get admin_posts_path(sort: "oldest")

    assert_response :success
    assert_operator response.body.index(older.title), :<, response.body.index(newer.title)
  end

  test "rss feed renders published posts" do
    get feed_path(format: :xml)

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, @post.title
  end

  test "article markdown renders diagrams images and escaped content" do
    @post.update!(
      body: "## 図解\n![構成図](images/remote-state-architecture.png)\n![画面](https://example.com/screen.png)\n<script>alert('xss')</script>"
    )

    get post_path(@post.slug)

    assert_response :success
    assert_includes response.body, "article-diagram"
    assert_includes response.body, "article-image"
    assert_includes response.body, "https://example.com/screen.png"
    assert_includes response.body, "&lt;script&gt;alert"
    assert_not_includes response.body, "<script>alert"
  end

  test "admin can create preview publish and delete a post" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    assert_difference("Post.count", 1) do
      post admin_posts_path, params: {
        post: {
          title: "新しい検証ログ",
          slug: "new-lab-note",
          excerpt: "新しい検証ログの要約です。",
          body: "## 検証内容\n1. 準備\n2. 実行\n3. 確認",
          category_id: @category.id,
          status: "draft",
          kind: "experiment",
          tag_names: "検証, AWS"
        }
      }
    end

    created = Post.find_by!(slug: "new-lab-note")
    assert created.draft?
    assert_redirected_to edit_admin_post_path(created.slug)

    get preview_admin_post_path(created.slug)
    assert_response :success
    assert_includes response.body, "新しい検証ログ"

    patch admin_post_path(created), params: {
      post: {
        title: created.title,
        slug: created.slug,
        excerpt: created.excerpt,
        body: created.body,
        category_id: @category.id,
        status: "published",
        kind: "experiment",
        tag_names: created.tag_names
      }
    }

    assert Post.find_by!(slug: "new-lab-note").published?

    assert_difference("Post.count", -1) do
      delete admin_post_path(created)
    end
  end

  test "future published posts stay hidden publicly but can be previewed by admin" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    future_time = 3.days.from_now.change(sec: 0)
    post admin_posts_path, params: {
      post: {
        title: "予約公開の記事",
        slug: "scheduled-post",
        excerpt: "未来日時までは公開しない記事です。",
        body: "## 予約公開\n公開前の本文です。",
        category_id: @category.id,
        status: "published",
        kind: "article",
        published_at: future_time.strftime("%Y-%m-%dT%H:%M"),
        tag_names: "Terraform"
      }
    }

    scheduled = Post.find_by!(slug: "scheduled-post")
    assert scheduled.published?
    assert_operator scheduled.published_at, :>, Time.current

    get posts_path
    assert_response :success
    assert_not_includes response.body, scheduled.title

    get post_path(scheduled.slug)
    assert_response :not_found

    get preview_admin_post_path(scheduled.slug)
    assert_response :success
    assert_includes response.body, scheduled.title
  end

  test "admin can update site settings and password" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    patch admin_settings_path, params: {
      site_setting: {
        blog_title: "Updated Tech Notes",
        tagline: "更新したキャッチコピー",
        site_url: "https://example.com",
        description: "更新したブログ説明です。",
        profile_name: "Updated Hiroe",
        profile_title: "SRE",
        profile_email: "updated@example.com",
        profile_bio: "更新したプロフィールです。",
        github_url: "https://github.com/example",
        x_url: "https://x.com/example",
        rss_url: "https://example.com/feed.xml",
        zenn_url: "https://zenn.dev/example",
        note_url: "https://note.com/example",
        profile_visible: "1",
        sns_visible: "1",
        default_theme: "light",
        posts_per_page: "5"
      },
      current_password: "password123",
      new_password: "newpass123",
      new_password_confirmation: "newpass123"
    }

    assert_redirected_to admin_settings_path
    assert_equal "Updated Tech Notes", @setting.reload.blog_title
    assert_equal 5, @setting.posts_per_page
    assert @admin.reload.authenticate("newpass123")
  end

  test "admin setting image uploads reject unsupported file types" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    invalid_upload = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/not-image.txt"),
      "text/plain"
    )

    patch admin_settings_path, params: {
      site_setting: {
        blog_title: @setting.blog_title,
        tagline: @setting.tagline,
        site_url: @setting.site_url,
        description: @setting.description,
        profile_name: @setting.profile_name,
        profile_title: @setting.profile_title,
        profile_email: @setting.profile_email,
        profile_bio: @setting.profile_bio,
        github_url: @setting.github_url,
        x_url: @setting.x_url,
        rss_url: @setting.rss_url,
        zenn_url: @setting.zenn_url,
        note_url: @setting.note_url,
        profile_visible: "1",
        sns_visible: "1",
        default_theme: @setting.default_theme,
        posts_per_page: @setting.posts_per_page,
        ogp_image: invalid_upload
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "OGP画像はJPGまたはPNGでアップロードしてください。"
    assert_not @setting.reload.ogp_image.attached?
  end
end

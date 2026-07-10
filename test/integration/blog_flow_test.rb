require "test_helper"
require "json"
require "tempfile"

class BlogFlowTest < ActionDispatch::IntegrationTest
  setup do
    @setting = SiteSetting.current
    @admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @category = Category.create!(name: "AWS", name_en: "AWS", slug: "aws", icon_key: "aws", position: 1)
    @ai_category = Category.create!(name: "AI開発", name_en: "AI Development", slug: "ai-development", icon_key: "code", position: 2)
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
    get "/en"
    assert_response :success
    assert_includes response.body, "Hiroe Tech Notes"
    assert_includes response.body, "Learn by doing"
    assert_not_includes response.body, admin_login_path
    assert_select "button[data-theme-toggle][aria-label='Toggle theme'][aria-pressed]"
    assert_select ".latest-posts .filter-tabs a[href='/en/posts?category=ai-development']", text: @ai_category.localized_name
    assert_select "pre.code-card.highlight.language-terraform code.highlight"
    assert_includes response.body, "<span"

    get "/en/posts"
    assert_response :success
    assert_includes response.body, @post.title

    get "/en/posts", params: { q: "terraform" }
    assert_response :success
    assert_includes response.body, @post.title

    get "/en/posts/terraform-remote-state"
    assert_response :success
    assert_includes response.body, "Terraform"
    assert_select "meta[property='og:type'][content='article']"
    assert_select "meta[property='og:url'][content='http://www.example.com/en/posts/terraform-remote-state']"
    assert_select "link[rel='canonical'][href='http://www.example.com/en/posts/terraform-remote-state']"
    assert_includes response.body, "code-block"
    assert_includes response.body, "https://x.com/intent/tweet"
    assert_includes response.body, "/en/feed"
    assert_select ".article-admin-actions .admin-edit-link[href='#{edit_admin_post_path(@post.slug)}']", count: 0

    get "/en/tags"
    assert_response :success
    assert_includes response.body, @tag.name

    get "/en/categories"
    assert_response :success
    assert_includes response.body, @category.localized_name

    assert_select "a[href='/en/posts?category=aws'] strong", text: "1"
    get "/en/archives"
    assert_response :success
    assert_includes response.body, "Archives"
    assert_includes response.body, @post.title

    get "/en/profile"
    assert_response :success
    assert_includes response.body, @setting.profile_name
    assert_includes response.body, @setting.profile_title
    assert_includes response.body, @setting.profile_email
    assert_includes response.body, @setting.github_url

    get "/en/about"
    assert_response :success
    assert_includes response.body, "Hiroe Tech Notes"
  end

  test "signed in admin can edit from the public post title" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    get "/en/posts/terraform-remote-state"
    assert_response :success
    assert_select "h1", text: @post.title
    assert_select ".article-content > h1 + .article-admin-actions .admin-edit-link[href^='/admin/posts/terraform-remote-state/edit']", text: "Edit"

    get edit_admin_post_path(@post.slug)
    assert_response :success
    assert_includes response.body, @post.title
  end

  test "public post markdown images are wired for in-page lightbox" do
    @post.update!(body: "## 構成例\n\n![構成図](/icon.png)")

    get "/en/posts/terraform-remote-state"
    assert_response :success

    assert_select ".markdown-body[data-image-lightbox]"
    assert_select ".markdown-body .article-image img.article-image-viewer-trigger[role='button'][tabindex='0'][src='/icon.png'][alt='構成図']"
  end

  test "post filters tolerate invalid month and experiment search stays on experiments path" do
    get "/en/posts", params: { month: "not-a-month" }
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

    get "/en/experiments", params: { q: "実験ログ検索対象" }
    assert_response :success
    assert_includes response.body, experiment.title
    assert_select "form[action='/en/experiments']"
    assert_select ".global-nav a.active", text: "Experiments"
    assert_select ".filter-tabs a[href^='/en/experiments'][href*='category=aws']", text: @category.localized_name
  end

  test "public post list can change sort order and reset filters" do
    older = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "古い公開記事",
      slug: "old-public-post",
      excerpt: "古い公開記事です。",
      body: "## 古い記事",
      status: :published,
      kind: :article,
      published_at: 3.days.ago
    )

    get "/en/posts", params: { sort: "oldest" }

    assert_response :success
    assert_operator response.body.index(older.title), :<, response.body.index(@post.title)
    assert_select "input[name='q'][aria-label='Search by title']"
    assert_select "select[name='sort'][aria-label='Sort order']"
    assert_select "select[name='sort'] option[selected='selected'][value='oldest']"
    assert_select "a.secondary-button[href='/en/posts']", text: "Reset"
  end

  test "public pagination clamps pages beyond the last page" do
    @setting.update!(posts_per_page: 5)

    get "/en/posts", params: { page: 99 }

    assert_response :success
    assert_includes response.body, @post.title
    assert_select ".page-count", text: "1 / 1 pages (1 total)"
  end

  test "top daily log prefers experiment posts over regular articles" do
    experiment = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "今日の実験ログ",
      slug: "today-experiment-log",
      excerpt: "今日の実験ログです。",
      body: "## 実験",
      status: :published,
      kind: :experiment,
      published_at: 1.day.ago
    )

    Post.create!(
      admin_user: @admin,
      category: @category,
      title: "さらに新しい通常記事",
      slug: "newer-regular-article",
      excerpt: "さらに新しい通常記事です。",
      body: "## 記事",
      status: :published,
      kind: :article,
      published_at: Time.current
    )

    get "/en"

    assert_response :success
    assert_select ".daily-card h2", text: experiment.title
  end

  test "top daily log does not reveal draft experiments" do
    Post.create!(
      admin_user: @admin,
      category: @category,
      title: "非公開の実験ログ",
      slug: "draft-experiment-log",
      excerpt: "非公開の実験ログです。",
      body: "## 実験",
      status: :draft,
      kind: :experiment
    )

    get "/en"

    assert_response :success
    assert_not_includes response.body, "非公開の実験ログ"
    assert_select ".daily-card h2", text: "TerraformでS3バケットを作ってみる"
  end

  test "top experiment cards show body image preview when post has markdown image" do
    experiment = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "画像あり実験",
      slug: "experiment-with-image",
      excerpt: "画像付き実験ログです。",
      body: "![構成図](https://example.com/diagram.png)\n\n実験内容です。",
      status: :published,
      kind: :experiment,
      published_at: Time.current
    )

    get "/en"
    assert_response :success
    assert_select ".experiment-card[href='#{post_path(experiment)}']" do
      assert_select "time", text: experiment.display_date.strftime("%Y-%m-%d")
      assert_select "h3", text: experiment.title
      assert_select ".experiment-card-preview img.experiment-card-image[src='https://example.com/diagram.png'][alt='構成図']"
      assert_select "p", text: experiment.excerpt
    end
  end

  test "top experiment cards show code preview when post has code block" do
    experiment = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "コード実験",
      slug: "experiment-with-code",
      excerpt: "コード付き実験ログです。",
      body: "```ruby\nputs 'hello'\n```\n\n実験内容です。",
      status: :published,
      kind: :experiment,
      published_at: Time.current
    )

    get "/en"
    assert_response :success
    assert_select ".experiment-card[href='#{post_path(experiment)}']" do
      assert_select "time", text: experiment.display_date.strftime("%Y-%m-%d")
      assert_select "h3", text: experiment.title
      assert_select ".experiment-card-preview pre.experiment-card-code"
      assert_select "p", text: experiment.excerpt
    end
  end

  test "top experiment card hides preview when post has no image or code block" do
    experiment = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "プレビューなし実験",
      slug: "experiment-no-preview",
      excerpt: "プレビューなし実験ログです。",
      body: "実験内容のみの本文です。",
      status: :published,
      kind: :experiment,
      published_at: Time.current
    )

    get "/en"
    assert_response :success
    assert_select ".experiment-card[href='#{post_path(experiment)}']" do
      assert_select "h3", text: experiment.title
      assert_select ".experiment-card-preview", count: 0
    end
  end

  test "post body_preview extracts first image and first code block correctly" do
    with_images = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "プレビュー抽出テスト",
      slug: "preview-extraction-test",
      excerpt: "テスト用",
      body: "![画像1](/img1.png) ![画像2](/img2.png)\n```ruby\nputs 'ignored'\n```",
      status: :published,
      kind: :experiment,
      published_at: Time.current
    )

    preview = with_images.body_preview
    assert_equal :image, preview[:type]
    assert_equal "/img1.png", preview[:url]
    assert_equal "画像1", preview[:alt]

    with_code = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "コードのみ",
      slug: "code-only-preview",
      excerpt: "テスト用",
      body: "本文\n```javascript\nconsole.log('hi')\n```\n以上",
      status: :published,
      kind: :experiment,
      published_at: Time.current
    )

    preview = with_code.body_preview
    assert_equal :code, preview[:type]
    assert_equal "console.log('hi')", preview[:code]
    assert_equal "javascript", preview[:language]

    without = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "プレビューなし",
      slug: "no-preview-at-all",
      excerpt: "テスト用",
      body: "本文のみ",
      status: :published,
      kind: :experiment,
      published_at: Time.current
    )

    assert_nil without.body_preview
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

    get "/en"
    assert_response :success
    assert_select "a[href='/en/posts?category=aws'] strong", text: "1"

    get "/en/tags"
    assert_response :success
    assert_includes response.body, @tag.name
    assert_not_includes response.body, draft_tag.name

    get "/en/categories"
    assert_response :success
    assert_includes response.body, @category.localized_name
    assert_not_includes response.body, draft_category.name
  end

  test "profile visibility setting hides public profile navigation and page" do
    @setting.update!(profile_visible: false)

    get "/en"
    assert_response :success
    assert_select ".global-nav a", text: "Profile", count: 0
    assert_not_includes response.body, "profile-card"

    get "/en/profile"
    assert_redirected_to root_path
  end

  test "sns visibility and blank urls do not render placeholder public links" do
    @setting.update!(github_url: "", x_url: "", zenn_url: "", note_url: "", sns_visible: true)

    get "/en/profile"
    assert_response :success
    assert_select ".profile-links a[href='#']", count: 0
    assert_select ".profile-links a", text: "RSS"

    @setting.update!(sns_visible: false)
    get "/en/profile"
    assert_response :success
    assert_select ".profile-links", count: 0
  end

  test "admin can sign in and view management pages" do
    get admin_posts_path
    assert_redirected_to admin_login_path

    get admin_login_path
    assert_response :success
    assert_includes response.body, I18n.t("admin.sessions.new.title")
    assert_select ".password-field input[type='password'][name='password']"
    assert_select ".password-field button[data-password-toggle][data-password-toggle-label='#{I18n.t("admin.sessions.new.password_label")}'][data-password-toggle-show='#{I18n.t("js.password_toggle.show")}'][data-password-toggle-hide='#{I18n.t("js.password_toggle.hide")}'][aria-label='#{I18n.t("js.password_toggle.show")}'][aria-pressed='false']", text: "◎"
    assert_not_includes response.body, "Global Navigation"
    assert_not_includes response.body, "Articles"
    assert_not_includes response.body, "href=\"#\""
    assert_includes response.body, "mailto:#{@setting.profile_email}"
    assert_includes response.body, "aria-label=\"#{I18n.t("shared.header.theme_toggle")}\""
    assert_includes response.body, "aria-label=\"#{I18n.t("shared.header.search")}\""

    post admin_login_path, params: { email: "", password: "" }
    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("flash.admin.sessions.email_blank")
    assert_includes response.body, I18n.t("flash.admin.sessions.password_blank")

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    follow_redirect!
    assert_response :success
    assert_includes response.body, I18n.t("admin.posts.index.title")
    assert_includes response.body, I18n.t("shared.header.logout")

    get "/en"
    assert_response :success
    assert_not_includes response.body, "ログアウト"
    assert_not_includes response.body, admin_posts_path

    get edit_admin_post_path(@post.slug)
    assert_response :success
    assert_includes response.body, "data-open-publish-modal"
    assert_includes response.body, "data-publish-modal-backdrop"
    assert_includes response.body, I18n.t("admin.posts.form.modal_title")
    assert_includes response.body, I18n.t("admin.posts.form.publish_submit")
    assert_includes response.body, "name=\"commit_status\" value=\"draft\""
    assert_includes response.body, "name=\"commit_status\" value=\"published\""
    assert_select "button[name='commit_status'][value='draft'][formnovalidate]", count: 2
    assert_select "button[name='commit_status'][value='published'][formnovalidate]", count: 0
    assert_includes response.body, I18n.t("admin.posts.form.published_at_label")
    assert_includes response.body, "data-md-action=\"bold\""
    assert_includes response.body, "aria-label=\"#{I18n.t("admin.posts.form.bold_aria")}\""
    assert_includes response.body, "aria-label=\"#{I18n.t("admin.posts.form.image_aria")}\""
    assert_select "input[type='file'][data-post-image-input][accept='image/jpeg,image/png,image/webp,image/gif']"
    assert_includes response.body, admin_post_images_path(@post)
    assert_includes response.body, I18n.t("admin.posts.form.attached_images")
    assert_includes response.body, "data-tag-input=\"true\""
    assert_select ".tag-preview .chip", text: @tag.name
    assert_includes response.body, "data-live-count-input=\"title\""
    assert_includes response.body, "data-body-stat=\"lines\""
    assert_includes response.body, "data-controller=\"post-summary\""
    assert_includes response.body, admin_post_summaries_path
    assert_includes response.body, admin_post_slugs_path
    assert_includes response.body, "aria-label=\"#{I18n.t("admin.posts.form.excerpt_ai_aria")}\""
    assert_includes response.body, "aria-label=\"#{I18n.t("admin.posts.form.slug_ai_aria")}\""
    assert_includes response.body, "data-tooltip=\"#{I18n.t("admin.posts.form.excerpt_ai_tooltip")}\""
    assert_includes response.body, "data-tooltip=\"#{I18n.t("admin.posts.form.slug_ai_tooltip")}\""
    assert_includes response.body, "data-post-summary-target=\"body\""
    assert_includes response.body, "data-post-summary-target=\"excerpt\""
    assert_includes response.body, "data-post-summary-target=\"slug\""
    assert_select "textarea[name='post[excerpt]'][data-post-summary-target='excerpt']"

    get new_admin_post_path
    assert_response :success
    assert_includes response.body, "data-open-editor-preview"
    assert_includes response.body, I18n.t("admin.posts.form.image_help_draft")
    assert_select "input[data-post-image-input]", count: 0
    assert_not_includes response.body, "href=\"#\""

    get preview_admin_post_path(@post.slug)
    assert_response :success
    assert_includes response.body, @post.title

    get admin_settings_path
    assert_response :success
    assert_includes response.body, I18n.t("admin.settings.show.h1")
    assert_includes response.body, "data-password-toggle"
    assert_select ".password-field button[data-password-toggle][data-password-toggle-label='#{I18n.t("admin.settings.show.current_password")}'][data-password-toggle-show='#{I18n.t("js.password_toggle.show")}'][data-password-toggle-hide='#{I18n.t("js.password_toggle.hide")}'][aria-label='#{I18n.t("js.password_toggle.show")}'][aria-pressed='false']"
    assert_select "input#site_setting_ogp_image[type='file']"
    assert_select "label[for='site_setting_ogp_image']", text: I18n.t("admin.settings.show.change_image")
    assert_select "input#site_setting_ogp_image[data-settings-image-input][data-preview-alt='OGP画像']"
    assert_select "[data-settings-image-preview-container] [data-settings-image-placeholder]", text: /Recommended:/
    assert_select "[data-settings-image-save-notice][hidden]", text: I18n.t("admin.settings.show.save_notice"), count: 2
    assert_select "input#site_setting_profile_image[type='file']"
    assert_select "label[for='site_setting_profile_image']", text: I18n.t("admin.settings.show.change_avatar")
    assert_select "input#site_setting_profile_image[data-settings-image-input][data-preview-alt='プロフィール画像']"
    assert_select "[data-settings-image-preview-container]", count: 2

    importmap_json = response.body[/<script type="importmap"[^>]*>(.*?)<\/script>/m, 1]
    application_asset_path = JSON.parse(importmap_json).fetch("imports").fetch("application")
    get application_asset_path
    assert_response :success
    assert_includes response.body, "data-settings-image-input"
    assert_includes response.body, "FileReader"

    application_source = Rails.root.join("app/javascript/application.js").read
    assert_includes application_source, "const updatePasswordToggle"
    assert_includes application_source, "input.type = visible ? \"text\" : \"password\""
    assert_includes application_source, "button.setAttribute(\"aria-pressed\", visible ? \"true\" : \"false\")"
    assert_includes application_source, "button.setAttribute(\"aria-label\", visible ? hideLabel : showLabel)"
  end

  test "admin management actions require sign in" do
    get new_admin_post_path
    assert_redirected_to admin_login_path

    get edit_admin_post_path(@post.slug)
    assert_redirected_to admin_login_path

    get preview_admin_post_path(@post.slug)
    assert_redirected_to admin_login_path

    get admin_settings_path
    assert_redirected_to admin_login_path

    post markdown_preview_admin_posts_path, params: { body: "* 非公開プレビュー" }
    assert_redirected_to admin_login_path

    post admin_post_images_path(@post), params: { image: valid_image_upload }
    assert_redirected_to admin_login_path

    post admin_post_summaries_path, params: { title: "未ログイン", body: "本文" }
    assert_redirected_to admin_login_path

    post admin_post_summaries_path, params: { title: "未ログイン", body: "本文" }, as: :json
    assert_response :unauthorized
    assert_includes response.parsed_body.fetch("error"), I18n.t("flash.admin.base.unauthorized_json")

    post admin_post_slugs_path, params: { title: "未ログイン", body: "本文" }
    assert_redirected_to admin_login_path

    post admin_post_slugs_path, params: { title: "未ログイン", body: "本文" }, as: :json
    assert_response :unauthorized
    assert_includes response.parsed_body.fetch("error"), I18n.t("flash.admin.base.unauthorized_json")

    delete admin_post_image_path(@post, 999)
    assert_redirected_to admin_login_path

    post admin_posts_path, params: {
      post: {
        title: "未ログイン投稿",
        slug: "anonymous-post",
        excerpt: "未ログイン投稿です。",
        body: "## 本文",
        category_id: @category.id,
        status: "published",
        kind: "article"
      }
    }
    assert_redirected_to admin_login_path
    assert_nil Post.find_by(slug: "anonymous-post")

    delete admin_post_path(@post.slug)
    assert_redirected_to admin_login_path
    assert Post.exists?(@post.id)
  end

  test "admin markdown preview renders with shared server renderer without saving" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    assert_no_difference("Post.count") do
      post markdown_preview_admin_posts_path, params: {
        body: <<~MARKDOWN
          * 箇条書き
          [リンク](https://example.com)
          ![画像](https://example.com/image.png)
        MARKDOWN
      }
    end

    assert_response :success
    assert_includes response.body, "<li>箇条書き</li>"
    assert_includes response.body, "href=\"https://example.com\""
    assert_includes response.body, "<img src=\"https://example.com/image.png\""
  end

  test "admin markdown preview escapes unsafe content like public renderer" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    post markdown_preview_admin_posts_path, params: {
      body: <<~MARKDOWN
        [危険なリンク](javascript:alert(1))
        ![危険な画像](javascript:alert(1))
        <script>alert('xss')</script>
      MARKDOWN
    }

    assert_response :success
    assert_not_includes response.body, "href=\"javascript:alert"
    assert_not_includes response.body, "<img src=\"javascript:alert"
    assert_not_includes response.body, "<script>alert"
    assert_not_includes response.body, "alert('xss')"
  end

  test "admin can generate post summary without saving the post" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    fake_generator = Object.new
    def fake_generator.generate(title:, body:)
      raise "unexpected title" unless title == "Terraformのリモートステート設計"
      raise "unexpected body" unless body.include?("S3")

      "Terraformのリモートステート設計について、構成例と運用上の注意点を整理した記事です。"
    end

    with_post_summary_generator(fake_generator) do
      assert_no_changes -> { @post.reload.excerpt } do
        post admin_post_summaries_path,
          params: { title: @post.title, body: @post.body },
          as: :json
      end
    end

    assert_response :success
    assert_equal "Terraformのリモートステート設計について、構成例と運用上の注意点を整理した記事です。", response.parsed_body.fetch("summary")
  end

  test "admin post summary generation validates input and reports ai failures" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    post admin_post_summaries_path, params: { title: "空本文", body: " " }, as: :json
    assert_response :bad_request
    assert_includes response.parsed_body.fetch("error"), "body text"

    fake_generator = Object.new
    def fake_generator.generate(title:, body:)
      raise PostSummaryGenerator::GenerationError, "Cloudflare Workers AI is not configured."
    end

    with_post_summary_generator(fake_generator) do
      post admin_post_summaries_path,
        params: { title: "設定不足", body: "本文" },
        as: :json
    end

    assert_response :bad_gateway
    assert_includes response.parsed_body.fetch("error"), "not configured"

    rate_limited_generator = Object.new
    def rate_limited_generator.generate(title:, body:)
      raise PostSummaryGenerator::RateLimitError, "Rate limit reached."
    end

    with_post_summary_generator(rate_limited_generator) do
      post admin_post_summaries_path,
        params: { title: "制限", body: "本文" },
        as: :json
    end

    assert_response :too_many_requests
    assert_includes response.parsed_body.fetch("error"), "Rate limit"
  end

  test "admin can generate post slug without saving the post" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    fake_generator = Object.new
    def fake_generator.generate(title:, body:)
      raise "unexpected title" unless title == "Aurora PostgreSQLへオンプレから移行期間中に接続する"
      raise "unexpected body" unless body.include?("Aurora")

      "aurora-postgresql-onprem-migration-access"
    end

    with_post_slug_generator(fake_generator) do
      assert_no_changes -> { @post.reload.slug } do
        post admin_post_slugs_path,
          params: {
            title: "Aurora PostgreSQLへオンプレから移行期間中に接続する",
            body: "AWSでAurora for PostgreSQLを使い、移行期間中はオンプレからもアクセスします。"
          },
          as: :json
      end
    end

    assert_response :success
    assert_equal "aurora-postgresql-onprem-migration-access", response.parsed_body.fetch("slug")
  end

  test "admin post slug generation validates input and reports ai failures" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    post admin_post_slugs_path, params: { title: " ", body: " " }, as: :json
    assert_response :bad_request
    assert_includes response.parsed_body.fetch("error"), "title or body"

    fake_generator = Object.new
    def fake_generator.generate(title:, body:)
      raise PostSlugGenerator::GenerationError, "Cloudflare Workers AI is not configured."
    end

    with_post_slug_generator(fake_generator) do
      post admin_post_slugs_path,
        params: { title: "設定不足", body: "本文" },
        as: :json
    end

    assert_response :bad_gateway
    assert_includes response.parsed_body.fetch("error"), "not configured"

    rate_limited_generator = Object.new
    def rate_limited_generator.generate(title:, body:)
      raise PostSlugGenerator::RateLimitError, "Rate limit reached."
    end

    with_post_slug_generator(rate_limited_generator) do
      post admin_post_slugs_path,
        params: { title: "制限", body: "本文" },
        as: :json
    end

    assert_response :too_many_requests
    assert_includes response.parsed_body.fetch("error"), "Rate limit"
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

  test "admin email is normalized for sign in" do
    mixed_case_admin = AdminUser.create!(
      email: "Owner@Example.COM ",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )

    assert_equal "owner@example.com", mixed_case_admin.email

    post admin_login_path, params: { email: "OWNER@example.com", password: "password123" }
    assert_redirected_to admin_posts_path
  end

  test "admin email must be a valid email address" do
    admin = AdminUser.new(email: "not-an-email")
    admin.password = "password123"

    assert_not admin.valid?
    assert_includes admin.errors[:email].join, "invalid"
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

    follow_redirect!
    assert_select ".flash.notice[data-flash-kind='notice']", text: I18n.t("flash.admin.posts.saved")
  end

  test "admin cannot save a post with an invalid slug" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    patch admin_post_path(@post), params: {
      post: {
        title: @post.title,
        slug: "invalid slug",
        excerpt: @post.excerpt,
        body: @post.body,
        category_id: @category.id,
        status: "published",
        kind: "article",
        tag_names: @post.tag_names
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("admin.posts.form.slug_pattern_title")
    assert_equal "terraform-remote-state", @post.reload.slug
  end

  test "admin save buttons override the status select value" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    patch admin_post_path(@post), params: {
      commit_status: "draft",
      post: {
        title: @post.title,
        slug: @post.slug,
        excerpt: @post.excerpt,
        body: @post.body,
        category_id: @category.id,
        status: "published",
        kind: "article",
        tag_names: @post.tag_names
      }
    }

    assert @post.reload.draft?

    patch admin_post_path(@post), params: {
      commit_status: "published",
      post: {
        title: @post.title,
        slug: @post.slug,
        excerpt: @post.excerpt,
        body: @post.body,
        category_id: @category.id,
        status: "draft",
        kind: "article",
        tag_names: @post.tag_names
      }
    }

    assert @post.reload.published?
  end

  test "admin can draft save a post without entering the hidden slug field" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    assert_difference("Post.count", 1) do
      post admin_posts_path, params: {
        commit_status: "draft",
        post: {
          title: "Hidden Slug Draft",
          slug: "",
          excerpt: "下書き保存の確認です。",
          body: "下書き本文です。",
          category_id: @category.id,
          status: "published",
          kind: "article",
          tag_names: ""
        }
      }
    end

    created = Post.find_by!(slug: "hidden-slug-draft")
    assert created.draft?
    assert_redirected_to edit_admin_post_path(created.slug)

    follow_redirect!
    assert_select ".flash.notice[data-flash-kind='notice']", text: I18n.t("flash.admin.posts.saved")
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

  test "admin post list searches titles case insensitively" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    get admin_posts_path(q: "terraform")

    assert_response :success
    assert_select "input[name='q'][aria-label='#{I18n.t("admin.posts.index.search_placeholder")}']"
    assert_select "select[name='category_id'][aria-label='Filter by category']"
    assert_select "select[name='status'][aria-label='Filter by status']"
    assert_select "select[name='sort'][aria-label='#{I18n.t("admin.posts.index.sort_aria")}']"
    assert_includes response.body, @post.title
  end

  test "admin pagination clamps pages beyond the last page" do
    @setting.update!(posts_per_page: 5)

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    get admin_posts_path(page: 99)

    assert_response :success
    assert_includes response.body, @post.title
    assert_select ".page-count", text: I18n.t("admin.posts.index.page_info", page: 1, total_pages: 1, count: 1)
  end

  test "rss feed renders published posts" do
    get "/en/feed.xml"

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, @post.title
  end

  test "article markdown renders diagrams images and escaped content" do
    @post.update!(
      body: <<~MARKDOWN
        ## 図解
        ![構成図](images/remote-state-architecture.png)
        ![画面](https://example.com/screen.png)
        ![危険な画像](javascript:alert(1))
        [公式ドキュメント](https://example.com/docs)
        [危険なリンク](javascript:alert(1))
        - [x] 手順を確認する
        - [ ] 後で見直す
        * アスタリスク箇条書き
        + プラス箇条書き
        | 項目 | 内容 |
        | --- | --- |
        | Backend | S3 |
        <script>alert('xss')</script>
      MARKDOWN
    )

    get "/en/posts/terraform-remote-state"

    assert_response :success
    assert_includes response.body, "article-diagram"
    assert_includes response.body, "article-image"
    assert_includes response.body, "https://example.com/screen.png"
    assert_not_includes response.body, "<img src=\"javascript:alert"
    assert_includes response.body, "href=\"https://example.com/docs\""
    assert_includes response.body, "task-list-item"
    assert_includes response.body, "checked"
    assert_includes response.body, "<li>アスタリスク箇条書き</li>"
    assert_includes response.body, "<li>プラス箇条書き</li>"
    assert_includes response.body, "markdown-table"
    assert_includes response.body, "<th>項目</th>"
    assert_includes response.body, "<td>S3</td>"
    assert_not_includes response.body, "href=\"javascript:alert"
    assert_not_includes response.body, "<script>alert"
    assert_not_includes response.body, "alert('xss')"
  end

  test "admin can upload insert metadata and delete post images" do
    with_public_storage_url("https://cdn.example.com") do
      post admin_login_path, params: { email: @admin.email, password: "password123" }

      assert_difference("ActiveStorage::Attachment.count", 1) do
        assert_difference("ActiveStorage::Blob.count", 1) do
          post admin_post_images_path(@post), params: { image: valid_image_upload }
        end
      end

      assert_response :created
      payload = JSON.parse(response.body)
      attachment = @post.reload.images.attachments.last
      assert_equal attachment.id, payload.fetch("id")
      assert_equal "screen.png", payload.fetch("filename")
      assert_equal "image/png", payload.fetch("content_type")
      assert_equal "https://cdn.example.com/#{attachment.blob.key}", payload.fetch("url")
      assert_equal "![screen](https://cdn.example.com/#{attachment.blob.key})", payload.fetch("markdown")

      get edit_admin_post_path(@post.slug)
      assert_response :success
      assert_includes response.body, "screen.png"
      assert_includes response.body, payload.fetch("url")
      assert_includes response.body, "data-insert-markdown"
      assert_includes response.body, I18n.t("admin.posts.form.delete_image_confirm")

      assert_difference("ActiveStorage::Attachment.count", -1) do
        assert_difference("ActiveStorage::Blob.count", -1) do
          delete admin_post_image_path(@post, attachment)
        end
      end

      assert_redirected_to edit_admin_post_path(@post.slug)
      assert_not @post.reload.images.attached?
    end
  end

  test "admin post image uploads require configured cdn and valid files" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    with_public_storage_url(nil) do
      assert_no_difference("ActiveStorage::Attachment.count") do
        post admin_post_images_path(@post), params: { image: valid_image_upload }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body.fetch("error"), "CDN URL"

    with_public_storage_url("https://cdn.example.com") do
      invalid_upload = Rack::Test::UploadedFile.new(
        Rails.root.join("test/fixtures/files/not-image.txt"),
        "text/plain"
      )

      assert_no_difference("ActiveStorage::Attachment.count") do
        post admin_post_images_path(@post), params: { image: invalid_upload }
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body.fetch("error"), I18n.t("flash.admin.post_images.invalid_type")

      oversize_file = Tempfile.new([ "large", ".png" ])
      oversize_file.binmode
      oversize_file.write("x" * (Post::IMAGE_MAX_SIZE + 1))
      oversize_file.rewind
      oversize_upload = Rack::Test::UploadedFile.new(oversize_file.path, "image/png", original_filename: "large.png")

      begin
        assert_no_difference("ActiveStorage::Attachment.count") do
          post admin_post_images_path(@post), params: { image: oversize_upload }
        end
      ensure
        oversize_file.close!
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body.fetch("error"), I18n.t("flash.admin.post_images.too_large")
    end
  end

  test "article table of contents links to generated markdown heading ids" do
    @post.update!(body: "## 日本語の見出し\n本文です。")

    get "/en/posts/terraform-remote-state"

    assert_response :success
    heading_id = "heading-#{Digest::SHA1.hexdigest("日本語の見出し")[0, 10]}"
    assert_select "h2[id='#{heading_id}']", text: "日本語の見出し"
    assert_select ".toc-list a[href='##{heading_id}']", text: "日本語の見出し"
  end

  test "article table of contents ignores heading markers inside code blocks" do
    @post.update!(
      body: <<~MARKDOWN
        ```markdown
        ## コード内の見出し
        ```
        ## 本文の見出し
      MARKDOWN
    )

    get "/en/posts/terraform-remote-state"

    assert_response :success
    assert_select ".toc-list a", text: "コード内の見出し", count: 0
    assert_select ".toc-list a", text: "本文の見出し"
  end

  test "markdown renderer keeps table and list markers inside code blocks literal" do
    @post.update!(
      body: <<~MARKDOWN
        ```text
        | not | table |
        * not a list
        ```
      MARKDOWN
    )

    get "/en/posts/terraform-remote-state"

    assert_response :success
    assert_includes response.body, "<pre class=\"code-block\"><code>"
    assert_includes response.body, "| not | table |"
    assert_includes response.body, "* not a list"
    assert_select ".markdown-body table", count: 0
    assert_select ".markdown-body ul", count: 0
  end

  test "article markdown highlights fenced code blocks with known languages" do
    @post.update!(
      body: <<~MARKDOWN
        ```ruby
        puts "hello"
        ```

        ```bash
        echo "hello"
        ```
      MARKDOWN
    )

    get "/en/posts/terraform-remote-state"

    assert_response :success
    assert_includes response.body, "code-block"
    assert_includes response.body, "language-ruby"
    assert_includes response.body, "language-shell"
    assert_not_includes response.body, "style="
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

    get "/en/posts"
    assert_response :success
    assert_not_includes response.body, scheduled.title

    get "/en/posts/scheduled-post"
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

  test "admin setting changes roll back when password update fails" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    original_title = @setting.blog_title

    patch admin_settings_path, params: {
      site_setting: {
        blog_title: "Should Not Persist",
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
        posts_per_page: @setting.posts_per_page
      },
      current_password: "wrong-password",
      new_password: "newpass123",
      new_password_confirmation: "newpass123"
    }

    assert_response :unprocessable_entity
    assert_equal original_title, @setting.reload.blog_title
    assert @admin.reload.authenticate("password123")
  end

  test "admin settings reject invalid urls theme and pagination" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    original_site_url = @setting.site_url

    patch admin_settings_path, params: {
      site_setting: {
        blog_title: @setting.blog_title,
        tagline: @setting.tagline,
        site_url: "javascript:https://example.com",
        description: @setting.description,
        profile_name: @setting.profile_name,
        profile_title: @setting.profile_title,
        profile_email: @setting.profile_email,
        profile_bio: @setting.profile_bio,
        github_url: "ftp://example.com/profile",
        x_url: @setting.x_url,
        rss_url: @setting.rss_url,
        zenn_url: @setting.zenn_url,
        note_url: @setting.note_url,
        profile_visible: "1",
        sns_visible: "1",
        default_theme: "neon",
        posts_per_page: "2"
      }
    }

    assert_response :unprocessable_entity
    assert_equal original_site_url, @setting.reload.site_url
    assert_includes response.body, "must be an http or https URL"
  end

  test "admin settings reject invalid profile email" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    patch admin_settings_path, params: {
      site_setting: {
        blog_title: @setting.blog_title,
        tagline: @setting.tagline,
        site_url: @setting.site_url,
        description: @setting.description,
        profile_name: @setting.profile_name,
        profile_title: @setting.profile_title,
        profile_email: "invalid-email",
        profile_bio: @setting.profile_bio,
        github_url: @setting.github_url,
        x_url: @setting.x_url,
        rss_url: @setting.rss_url,
        zenn_url: @setting.zenn_url,
        note_url: @setting.note_url,
        profile_visible: "1",
        sns_visible: "1",
        default_theme: @setting.default_theme,
        posts_per_page: @setting.posts_per_page
      }
    }

    assert_response :unprocessable_entity
    assert_not_equal "invalid-email", @setting.reload.profile_email
    assert_includes response.body, "invalid"
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
    assert_includes response.body, "OGP image must be JPG or PNG"
    assert_not @setting.reload.ogp_image.attached?
  end

  test "article show page has comments section" do
    get "/en/posts/terraform-remote-state"
    assert_response :success
    assert_select "#comments"
    assert_select ".comment-form-wrap form"
    assert_select "input[name='comment[author_name]']"
    assert_select "textarea[name='comment[body]']"
    assert_select "input[type='submit'][value='Post comment']"
  end

  test "visitor can post a comment with valid turnstile" do
    post "/en/posts/terraform-remote-state/comments", params: {
      comment: { author_name: "テスト太郎", body: "参考になりました！" },
      "cf-turnstile-response" => "dummy-token"
    }
    assert_redirected_to post_path(@post, anchor: "comments")
    follow_redirect!
    assert_includes response.body, "Comment posted"

    get "/en/posts/terraform-remote-state"
    assert_includes response.body, "テスト太郎"
    assert_includes response.body, "参考になりました！"
  end

  test "visitor cannot post comment without turnstile" do
    post "/en/posts/terraform-remote-state/comments", params: {
      comment: { author_name: "テスト太郎", body: "参考になりました！" }
    },
    as: :html
    assert_response :unprocessable_entity
    assert_includes response.body, "Flagged as spam"
  end

  test "visitor cannot post comment with empty name" do
    post "/en/posts/terraform-remote-state/comments", params: {
      comment: { author_name: "", body: "参考になりました！" },
      "cf-turnstile-response" => "dummy-token"
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "Author name"
  end

  test "visitor cannot post comment with empty body" do
    post "/en/posts/terraform-remote-state/comments", params: {
      comment: { author_name: "テスト太郎", body: "" },
      "cf-turnstile-response" => "dummy-token"
    }
    assert_response :unprocessable_entity
  end

  test "admin can view comment management page" do
    @post.comments.create!(author_name: "テスト太郎", body: "参考になりました！", ip_address: "127.0.0.1")

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    get admin_comments_path
    assert_response :success
    assert_includes response.body, "テスト太郎"
    assert_includes response.body, "参考になりました！"
    assert_select "a[href='/en/posts/terraform-remote-state']", text: @post.title
  end

  test "admin can delete a comment" do
    comment = @post.comments.create!(author_name: "テスト太郎", body: "削除対象", ip_address: "127.0.0.1")

    post admin_login_path, params: { email: @admin.email, password: "password123" }

    assert_difference -> { Comment.count }, -1 do
      delete admin_comment_path(comment)
    end
    assert_redirected_to admin_comments_path
    follow_redirect!
    assert_includes response.body, I18n.t("flash.comments.destroyed")
  end

  test "unauthenticated user cannot access admin comments" do
    get admin_comments_path
    assert_redirected_to admin_login_path
  end

  test "admin sees unread badge when comments exist" do
    @post.comments.create!(author_name: "テスト太郎", body: "未読コメント", ip_address: "127.0.0.1")
    @admin.update!(last_comments_read_at: 1.hour.ago)

    post admin_login_path, params: { email: @admin.email, password: "password123" }

    get admin_posts_path
    assert_response :success
    assert_select ".badge-dot"
  end

  test "admin does not see badge after viewing comments page" do
    @post.comments.create!(author_name: "テスト太郎", body: "既読コメント", ip_address: "127.0.0.1")

    post admin_login_path, params: { email: @admin.email, password: "password123" }

    get admin_comments_path
    assert_response :success

    get admin_posts_path
    assert_response :success
    assert_select ".badge-dot", count: 0
  end

  test "admin does not see badge when there are no comments" do
    @admin.update!(last_comments_read_at: Time.current)

    post admin_login_path, params: { email: @admin.email, password: "password123" }

    get admin_posts_path
    assert_response :success
    assert_select ".badge-dot", count: 0
  end

  test "publishing a post stores the admin locale source and enqueues translation" do
    post admin_login_path,
      params: { email: @admin.email, password: "password123" },
      headers: { "Accept-Language" => "ja" }

    assert_enqueued_jobs 1, only: TranslatePostJob do
      patch admin_post_path(@post),
        params: {
          commit_status: "published",
          post: {
            title: "更新後の日本語タイトル",
            slug: @post.slug,
            excerpt: "更新後の日本語要約です。",
            body: "## 更新後の本文\n\n日本語の内容です。",
            category_id: @category.id,
            status: "draft",
            kind: "article",
            tag_names: @post.tag_names
          }
        },
        headers: { "Accept-Language" => "ja" }
    end

    assert_redirected_to edit_admin_post_path(@post.slug)
    source = @post.post_translations.find_by!(locale: "ja")
    assert_equal "更新後の日本語タイトル", source.title
    assert_equal "## 更新後の本文\n\n日本語の内容です。", source.body
    assert_not @post.post_translations.exists?(locale: "en")
  end

  test "draft and reviewing saves do not enqueue translation" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }

    %w[draft reviewing].each do |status|
      assert_no_enqueued_jobs only: TranslatePostJob do
        patch admin_post_path(@post), params: {
          commit_status: status,
          post: {
            title: "#{status} title",
            slug: @post.slug,
            excerpt: "#{status} excerpt",
            body: "#{status} body",
            category_id: @category.id,
            status: "published",
            kind: "article",
            tag_names: @post.tag_names
          }
        }
      end
      assert @post.reload.public_send("#{status}?")
    end
  end

  test "public pages display and search persisted content for the current locale" do
    @post.post_translations.create!(
      locale: "en",
      title: "English translated title",
      excerpt: "English translated excerpt",
      body: "## English heading\n\nEnglish translated body",
      content_digest: "en-digest"
    )
    @post.post_translations.create!(
      locale: "ja",
      title: "日本語の翻訳タイトル",
      excerpt: "日本語の翻訳要約",
      body: "## 日本語の見出し\n\n日本語の翻訳本文",
      content_digest: "ja-digest"
    )

    get "/en/posts/#{@post.slug}"
    assert_response :success
    assert_select "h1", text: "English translated title"
    assert_includes response.body, "English translated body"
    assert_select "meta[name='description'][content='English translated excerpt']"

    get "/ja/posts/#{@post.slug}"
    assert_response :success
    assert_select "h1", text: "日本語の翻訳タイトル"
    assert_includes response.body, "日本語の翻訳本文"

    get "/en/posts", params: { q: "English translated" }
    assert_response :success
    assert_includes response.body, "English translated title"

    get "/ja/posts", params: { q: "English translated" }
    assert_response :success
    assert_not_includes response.body, "English translated title"
  end

  test "admin editor uses its current locale content" do
    @post.post_translations.create!(
      locale: "ja",
      title: "管理画面の日本語タイトル",
      excerpt: "管理画面の日本語要約",
      body: "管理画面の日本語本文",
      content_digest: "ja-digest"
    )
    post admin_login_path,
      params: { email: @admin.email, password: "password123" },
      headers: { "Accept-Language" => "ja" }

    get edit_admin_post_path(@post.slug), headers: { "Accept-Language" => "ja" }

    assert_response :success
    assert_select "input[name='post[title]'][value='管理画面の日本語タイトル']"
    assert_select "textarea[name='post[body]']", text: "管理画面の日本語本文"
    assert_select "textarea[name='post[excerpt]']", text: "管理画面の日本語要約"
  end

  private

  def with_post_summary_generator(generator)
    original_new = PostSummaryGenerator.method(:new)
    PostSummaryGenerator.define_singleton_method(:new) { |*| generator }
    yield
  ensure
    PostSummaryGenerator.define_singleton_method(:new) { |*args, **kwargs| original_new.call(*args, **kwargs) }
  end

  def with_post_slug_generator(generator)
    original_new = PostSlugGenerator.method(:new)
    PostSlugGenerator.define_singleton_method(:new) { |*| generator }
    yield
  ensure
    PostSlugGenerator.define_singleton_method(:new) { |*args, **kwargs| original_new.call(*args, **kwargs) }
  end

  def valid_image_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/not-image.txt"),
      "image/png",
      original_filename: "screen.png"
    )
  end

  test "admin category management requires sign in" do
    get admin_categories_path
    assert_redirected_to admin_login_path

    get new_admin_category_path
    assert_redirected_to admin_login_path

    post admin_categories_path, params: { category: { name: "Test", slug: "test" } }
    assert_redirected_to admin_login_path
  end

  test "admin can list create edit and delete categories" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    get admin_categories_path
    assert_response :success
    assert_includes response.body, @category.name
    assert_includes response.body, @category.name_en
    assert_includes response.body, I18n.t("admin.categories.index.new_category")

    assert_difference("Category.count", 1) do
      post admin_categories_path, params: {
        category: {
          name: "テストカテゴリー",
          name_en: "Test Category",
          slug: "test-category",
          icon_key: "code",
          position: 10
        }
      }
    end
    assert_redirected_to admin_categories_path
    follow_redirect!
    assert_includes response.body, I18n.t("flash.admin.categories.created")

    created = Category.find_by!(slug: "test-category")
    assert_equal "テストカテゴリー", created.name
    assert_equal "Test Category", created.name_en

    get edit_admin_category_path(created)
    assert_response :success
    assert_includes response.body, "テストカテゴリー"

    patch admin_category_path(created), params: {
      category: { name: "更新カテゴリー", name_en: "Updated Category" }
    }
    assert_redirected_to admin_categories_path
    assert_equal "更新カテゴリー", created.reload.name
    assert_equal "Updated Category", created.name_en

    follow_redirect!
    assert_includes response.body, I18n.t("flash.admin.categories.saved")

    assert_difference("Category.count", -1) do
      delete admin_category_path(created)
    end
    assert_redirected_to admin_categories_path
    follow_redirect!
    assert_includes response.body, I18n.t("flash.admin.categories.destroyed")
  end

  test "admin cannot delete a category that has posts" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    assert_no_difference("Category.count") do
      delete admin_category_path(@category)
    end
    assert_redirected_to admin_categories_path
    follow_redirect!
    assert_includes response.body, I18n.t("flash.admin.categories.restricted")
  end

  test "admin category creation validates required fields" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    follow_redirect!

    post admin_categories_path, params: { category: { name: "", slug: "" } }
    assert_response :unprocessable_entity
    assert_match /can&#39;t be blank/, response.body
  end

  def with_public_storage_url(url)
    previous = ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"]
    if url.nil?
      ENV.delete("ACTIVE_STORAGE_PUBLIC_BASE_URL")
    else
      ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"] = url
    end
    yield
  ensure
    ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"] = previous
  end
end

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
    assert_not_includes response.body, "管理者ログイン"
    assert_not_includes response.body, admin_login_path
    assert_select "button[data-theme-toggle][aria-label='テーマ切り替え'][aria-pressed]"

    get posts_path
    assert_response :success
    assert_includes response.body, @post.title

    get posts_path(q: "terraform")
    assert_response :success
    assert_includes response.body, @post.title

    get post_path(@post.slug)
    assert_response :success
    assert_includes response.body, "Terraform"
    assert_select "meta[property='og:type'][content='article']"
    assert_select "meta[property='og:url'][content='#{post_url(@post.slug)}']"
    assert_select "link[rel='canonical'][href='#{post_url(@post.slug)}']"
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

    get profile_path
    assert_response :success
    assert_includes response.body, @setting.profile_name
    assert_includes response.body, @setting.profile_title
    assert_includes response.body, @setting.profile_email
    assert_includes response.body, @setting.github_url

    get about_path
    assert_response :success
    assert_includes response.body, "Hiroe Tech Notes"
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
    assert_select ".global-nav a.active", text: "実験ログ"
    assert_select ".filter-tabs a[href^='#{experiments_path}'][href*='category=#{@category.slug}']", text: @category.name
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

    get posts_path(sort: "oldest")

    assert_response :success
    assert_operator response.body.index(older.title), :<, response.body.index(@post.title)
    assert_select "input[name='q'][aria-label='タイトルで検索']"
    assert_select "select[name='sort'][aria-label='並び順']"
    assert_select "select[name='sort'] option[selected='selected'][value='oldest']"
    assert_select "a.secondary-button[href='#{posts_path}']", text: "リセット"
  end

  test "public pagination clamps pages beyond the last page" do
    @setting.update!(posts_per_page: 5)

    get posts_path(page: 99)

    assert_response :success
    assert_includes response.body, @post.title
    assert_select ".page-count", text: "1 / 1 ページ（全1件）"
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

    get root_path

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

    get root_path

    assert_response :success
    assert_not_includes response.body, "非公開の実験ログ"
    assert_select ".daily-card h2", text: "TerraformでS3バケットを作ってみる"
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

  test "profile visibility setting hides public profile navigation and page" do
    @setting.update!(profile_visible: false)

    get root_path
    assert_response :success
    assert_select ".global-nav a", text: "プロフィール", count: 0
    assert_not_includes response.body, "profile-card"

    get profile_path
    assert_redirected_to root_path
  end

  test "sns visibility and blank urls do not render placeholder public links" do
    @setting.update!(github_url: "", x_url: "", zenn_url: "", note_url: "", sns_visible: true)

    get profile_path
    assert_response :success
    assert_select ".profile-links a[href='#']", count: 0
    assert_select ".profile-links a", text: "RSS"

    @setting.update!(sns_visible: false)
    get profile_path
    assert_response :success
    assert_select ".profile-links", count: 0
  end

  test "admin can sign in and view management pages" do
    get admin_posts_path
    assert_redirected_to admin_login_path

    get admin_login_path
    assert_response :success
    assert_includes response.body, "ログイン"
    assert_includes response.body, "aria-label=\"パスワードの表示切り替え\""
    assert_not_includes response.body, "グローバルナビゲーション"
    assert_not_includes response.body, "記事一覧"
    assert_not_includes response.body, "管理者ログイン"
    assert_not_includes response.body, "href=\"#\""
    assert_includes response.body, "mailto:#{@setting.profile_email}"
    assert_includes response.body, "aria-label=\"テーマ切り替え\""
    assert_includes response.body, "aria-label=\"検索\""

    post admin_login_path, params: { email: "", password: "" }
    assert_response :unprocessable_entity
    assert_includes response.body, "メールアドレスを入力してください。"
    assert_includes response.body, "パスワードを入力してください。"

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    follow_redirect!
    assert_response :success
    assert_includes response.body, "記事一覧"
    assert_includes response.body, "ログアウト"

    get root_path
    assert_response :success
    assert_not_includes response.body, "ログアウト"
    assert_not_includes response.body, admin_posts_path

    get edit_admin_post_path(@post.slug)
    assert_response :success
    assert_includes response.body, "Markdown"
    assert_includes response.body, "公開予約"
    assert_includes response.body, "name=\"commit_status\" value=\"draft\""
    assert_includes response.body, "name=\"commit_status\" value=\"published\""
    assert_includes response.body, "公開日時"
    assert_includes response.body, "data-md-action=\"bold\""
    assert_includes response.body, "aria-label=\"太字を挿入\""
    assert_includes response.body, "aria-label=\"画像を挿入\""
    assert_includes response.body, "data-tag-input=\"true\""
    assert_select ".tag-preview .chip", text: @tag.name
    assert_includes response.body, "data-live-count-input=\"title\""
    assert_includes response.body, "data-body-stat=\"lines\""

    get new_admin_post_path
    assert_response :success
    assert_includes response.body, "data-open-editor-preview"
    assert_not_includes response.body, "href=\"#\""

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
    assert_includes admin.errors[:email].join, "形式"
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
    assert_includes response.body, "半角英数字とハイフン"
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
    assert_select "input[name='q'][aria-label='タイトルで検索']"
    assert_select "select[name='category_id'][aria-label='カテゴリーで絞り込み']"
    assert_select "select[name='status'][aria-label='ステータスで絞り込み']"
    assert_select "select[name='sort'][aria-label='並び順']"
    assert_includes response.body, @post.title
  end

  test "admin pagination clamps pages beyond the last page" do
    @setting.update!(posts_per_page: 5)

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    get admin_posts_path(page: 99)

    assert_response :success
    assert_includes response.body, @post.title
    assert_select ".page-count", text: "1 / 1 ページ（全1件）"
  end

  test "rss feed renders published posts" do
    get feed_path(format: :xml)

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

    get post_path(@post.slug)

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

  test "article table of contents links to generated markdown heading ids" do
    @post.update!(body: "## 日本語の見出し\n本文です。")

    get post_path(@post.slug)

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

    get post_path(@post.slug)

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

    get post_path(@post.slug)

    assert_response :success
    assert_includes response.body, "<pre class=\"code-block\"><code>"
    assert_includes response.body, "| not | table |"
    assert_includes response.body, "* not a list"
    assert_select ".markdown-body table", count: 0
    assert_select ".markdown-body ul", count: 0
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
    assert_includes response.body, "httpまたはhttps"
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
    assert_includes response.body, "形式"
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

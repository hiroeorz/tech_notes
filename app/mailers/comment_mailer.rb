class CommentMailer < ApplicationMailer
  def new_comment(comment)
    @comment = comment
    @post = comment.post
    @site_setting = SiteSetting.current

    mail(
      to: @site_setting.profile_email,
      subject: t(".subject", site_name: @site_setting.blog_title, post_title: @post.localized_title)
    )
  end
end

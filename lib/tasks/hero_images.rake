namespace :hero_images do
  desc "Enqueue OGP hero image generation for published posts"
  task warm: :environment do
    Post.published.find_each do |post|
      GenerateHeroImageJob.perform_later(post.id)
    end
  end
end

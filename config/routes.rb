Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "llms.txt", to: "llms_txt#show"

  scope "(:locale)", locale: /en|ja/ do
    root "home#index"

    get "feed", to: "posts#feed", defaults: { format: :xml }, as: :feed
    get "feed.xml", to: "posts#feed", defaults: { format: :xml }
    resources :posts, only: [ :index, :show ], param: :slug do
      resources :comments, only: [ :create ]
    end
    get "experiments", to: "posts#index", defaults: { kind: "experiment" }, as: :experiments
    get "categories", to: "posts#categories", as: :categories
    get "tags", to: "posts#tags", as: :tags
    get "archives", to: "posts#archives", as: :archives
    get "profile", to: "home#profile", as: :profile
    get "about", to: "home#about", as: :about
  end

  post "locale", to: "locale#update"

  namespace :admin do
    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout
    resources :posts, param: :slug do
      member do
        get :preview
      end
      collection do
        post :markdown_preview
      end
      resources :images, only: [ :create, :destroy ], controller: "post_images"
    end
      resources :categories do
        resource :name_translation, only: [ :create ], controller: "category_name_translations"
      end
    resources :post_summaries, only: [ :create ]
    resource :profile_translation, only: [ :create ], controller: "profile_translations"
    resources :post_slugs, only: [ :create ]
    resources :comments, only: [ :index, :destroy ]
    resource :settings, only: [ :show, :update ]
    root "posts#index"
  end
end

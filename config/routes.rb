Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Documentation page at /docs
  get "docs", to: "high_voltage/pages#show", id: "docs"

  # Webhooks - SNS notifications from AWS SES
  post "webhooks/sns", to: "webhooks#sns", as: :sns_webhook

  # Tracking - Email opens and link clicks
  get "t/o/:token", to: "tracking#open", as: :track_open
  get "t/c/:token", to: "tracking#click", as: :track_click

  # Image short URLs
  get "i/:slug", to: "images#show", as: :short_image

  # Subscriptions - Unsubscribe and subscription forms
  get "unsubscribe/:token", to: "subscriptions#unsubscribe", as: :unsubscribe
  post "unsubscribe/:token", to: "subscriptions#unsubscribe_confirm", as: :unsubscribe_confirm
  get "subscribe/:list_id", to: "subscriptions#new", as: :subscribe
  post "subscribe/:list_id", to: "subscriptions#create", as: :create_subscription
  get "confirm_subscription/:token", to: "subscriptions#confirm", as: :confirm_subscription

  # Authenticated web dashboard
  authenticate :user do
    get "dashboard", to: "dashboard#index", as: :authenticated_root

    # Account setup wizard
    get "setup", to: "setup#show"
    post "setup/account_details", to: "setup#account_details", as: :setup_account_details
    post "setup/aws_credentials", to: "setup#aws_credentials", as: :setup_aws_credentials
    post "setup/logo", to: "setup#logo", as: :setup_logo
    post "setup/skip_logo", to: "setup#skip_logo", as: :setup_skip_logo

    resources :lists
    resources :subscribers do
      collection do
        get :import
        post :import_csv
        get :suppressed
      end
      member do
        post :reactivate
      end
    end
    resources :segments
    resources :campaigns do
      member do
        post :schedule
        post :send_now
        post :pause
        post :resume
        post :cancel
        post :send_test
        get :stats
        get :preview
      end
      collection do
        get :search_subscribers
      end
    end
    resources :templates do
      member do
        get :preview
      end
    end
    resources :images, only: [:create]
    resource :account, only: [:show, :edit, :update]
  end

  # API v1 - RESTful API with bearer token authentication
  namespace :api do
    namespace :v1 do
      # Subscribers
      resources :subscribers, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :unsubscribe
          post :resubscribe
        end
      end

      # Lists
      resources :lists, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :subscribers
          post :subscribers, action: :add_subscriber
          delete "subscribers/:subscriber_id", action: :remove_subscriber
        end
      end

      # Segments
      resources :segments, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :subscribers
          post :refresh
        end
      end

      # Campaigns
      resources :campaigns, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :schedule
          post :send_now
          post :pause
          post :resume
          post :cancel
          get :stats
        end
      end

      # Templates
      resources :templates, only: [:index, :show, :create, :update, :destroy]

      # API Keys
      resources :api_keys, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :revoke
        end
      end
    end
  end

  # Defines the root path route ("/")
  # Unauthenticated users see marketing page, authenticated users see dashboard
  root to: "high_voltage/pages#show", id: "home"
end

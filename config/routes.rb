Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "full_refresh#index"

  mount GoodJob::Engine => '/good_job'

  # Airtable webhook endpoint
  post 'airtable/webhook', to: 'airtable/webhooks#receive'
  
  # API routes
  namespace :api do
    post 'convert_address_to_parts', to: 'address#convert_to_parts'
  end

  # Full refresh routes
  resources :full_refresh, only: [:index, :create]
end

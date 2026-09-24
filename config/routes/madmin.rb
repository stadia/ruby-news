# typed: false
# Below are the routes for madmin
# rbs_inline: enabled

namespace :madmin do
  namespace :active_storage do
    resources :attachments
  end
  resources :preferences
  resources :tags
  resources :articles do
    member do
      put :discard
      put :restore
      put :mark_unrelated
      put :reprocess
      put :regenerate_thumbnail
      put :translate_japanese
    end
  end
  resources :sites do
    member do
      put :discard
      put :restore
    end
  end
  resources :users
  resources :roles

  # Social 메뉴 - OAuth 인증
  get "social", to: "social#index", as: :social_index

  root to: "dashboard#show"
end

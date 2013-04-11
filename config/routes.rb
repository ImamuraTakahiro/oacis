AcmProto::Application.routes.draw do

  resources :simulators, :only => ["index", "show"] do
    resources :parameters, :only => ["show"] do
      resources :runs, :only => ["show","create"]
    end
  end

  authenticated :user do
    root :to => 'home#index'
  end
  root :to => "home#index"
  devise_for :users
  resources :users
end
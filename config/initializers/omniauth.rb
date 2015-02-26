MENDELEY_CONSUMER_KEY = '1515'
MENDELEY_CONSUMER_SECRET = 'pgsPgCYa7A1MLVdm'
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :facebook, Rails.application.secrets.omniauth_provider_key, Rails.application.secrets.omniauth_provider_secret
  provider :mendeley, MENDELEY_CONSUMER_KEY, MENDELEY_CONSUMER_SECRET 
end

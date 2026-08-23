class ApplicationController < ActionController::Base
  # Camaleon's CamaleonController subclasses the host app's ApplicationController, so the dummy must
  # define one for the CMS (and this plugin's controllers) to eager-load.
  protect_from_forgery with: :exception
end

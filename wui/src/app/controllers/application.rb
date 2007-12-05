# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  # Pick a unique cookie name to distinguish our session data from others'
  session :session_key => '_invirt-webapp_session_id'
  init_gettext "invirt"
  layout 'default'

  def get_login_user
    user_from_principal(request.env["HTTP_X_FORWARDED_USER"])
  end
  
  def get_login_user_id
    User.find_by_ldap_uid(get_login_user)
  end
  
  def user_from_principal(principal)
    principal.split('@')[0]
  end
end
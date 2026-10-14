class ApplicationController < ActionController::API
  before_action :authenticate

  private

  def authenticate
    head :unauthorized unless current_account
  end

  def current_account
    @current_account ||= Account.find_by(api_token: request.headers["X-Token"]) if request.headers["X-Token"].present?
  end
end

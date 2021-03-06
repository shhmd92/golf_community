class EventsController < ApplicationController
  include CommonActions

  before_action :authenticate_user!, only: %i[create destroy]
  before_action :correct_user, only: :destroy

  MAX_PAGE = 20

  def index
    initial_search
  end

  def new
    @event = current_user.events.build if user_signed_in?
  end

  def show
    # イベントが見つからない場合は例外を発生させる
    @event = Event.find_by!(url_token: params[:url_token])
    @like = Like.new
    @comments = @event.comments.order(created_at: :desc)
    @comment = Comment.new
    @wheather_condition = []

    course_info = RakutenWebService::Gora::CourseDetail.search(golfCourseId: @event.course_id)
    begin
      unless course_info.nil?
        course_info_first = course_info.first
        @route_map_url = course_info_first['routeMapUrl']
        latitude = course_info_first['latitude']
        longitude = course_info_first['longitude']

        wheatherforecast = WeatherForecast.new(latitude, longitude)
        @wheather_condition = wheatherforecast.weather_condition(@event.event_date)
      end
    rescue StandardError => e
      logger.debug(e.backtrace.join("\n"))
    end

    # 主催者の場合、イベントに参加していない招待可能なユーザーを取得。
    if user_signed_in?
      if current_user.id == @event.user_id
        @invitable_users = User.invitable_users(@event)
      end
    end
  end

  def create
    @event = current_user.events.build(event_params)
    if @event.save
      current_user.participants.create(event_id: @event.id)
      flash[:notice] = 'イベントを作成しました'
      redirect_to event_path(@event)
    else
      render 'new'
    end
  end

  def destroy
    @event.destroy
    flash[:notice] = 'イベントを削除しました'
    path = Rails.application.routes.recognize_path(request.referer)

    if path[:controller] == 'events'
      redirect_to root_path
    else
      redirect_back(fallback_location: root_path)
    end
  end

  def edit
    @event = Event.find_by(url_token: params[:url_token])
  end

  def update
    @event = Event.find_by(url_token: params[:url_token])
    if @event.update(event_params)
      flash[:notice] = 'イベントを更新しました'
      redirect_to event_path(@event)
    else
      render 'edit'
    end
  end

  def search
    search_events

    render action: :index
  end

  def autocomplete_search
    places = {}

    if params[:term]
      courses = RakutenWebService::Gora::Course.search(keyword: params[:term].to_s)
      courses.each do |course|
        golf_course_id = course['golfCourseId']
        golf_course_abbr = course['golfCourseAbbr']
        golf_course_abbr = golf_course_abbr.to_s + '[' + golf_course_id.to_s + ']'
        places[golf_course_id] = golf_course_abbr
      end
    end
    render json: places.to_json
  end

  def golf_course_info
    course_info = RakutenWebService::Gora::CourseDetail.search(golfCourseId: params[:course_id])

    unless course_info.nil?
      course_info_first = course_info.first
      address = course_info_first['address']
      golf_course_image_url = course_info_first['golfCourseImageUrl1']
      respond_to do |format|
        format.json do
          render json: { address: address,
                         golf_course_image_url: golf_course_image_url }, status: :ok
        end
      end
    end
  end

  def invite
    @event = Event.find_by!(url_token: params[:url_token])
    params[:event][:user_ids].each do |user_id|
      @event.create_notification_invite!(user_id) if user_id.to_i >= 1
    end

    flash[:notice] = 'ゴル友を招待しました'
    redirect_to event_path(@event)
  end

  private

  def event_params
    params.require(:event).permit(:title, :content, :place, :address, :maximum_participants, :image,
                                  :remote_image_url, :event_date, :start_time, :end_time, :course_id)
  end

  def correct_user
    @event = current_user.events.find_by(url_token: params[:url_token])
    if @event.nil? && current_user.admin?
      @event = Event.find_by(url_token: params[:url_token])
    end
    redirect_to root_url if @event.nil?
  end
end

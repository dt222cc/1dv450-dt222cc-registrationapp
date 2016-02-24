class Api::V1::EventsController < Api::V1::ApiController
  before_action :restrict_access
  before_action :check_authorization, only: [:create, :destroy, :update]

  # GET /api/v1/events
  def index
    events = Event.all

    if events.nil?
      render json: { error: 'No events found'}, status: :not_found
    else
      render json: events, status: :ok
    end
  end

  #GET /api/v1/events/:id
  def show
    event = Event.find_by_id(params[:id])

    if tag.nil?
      render json: { error: 'Event was not found. Provided ID does not exist.' }, status: :not_found
    else
      render json: event, status: :ok
    end
  end

  # POST /api/v1/events
  # Creates an event to current creator, only if authentication passed
  # Tried to covert some parts to helper method for reuseability, issues with the render json part
  def create
    begin # Initialize and check if "event" can be found in the request
      event = Event.new(event_params.except(:tags, :position))
      position = Position.new(event_params[:position])
    rescue
      # Friendly error response, should contain event obj.
      render json: event_param_error_response, status: :unprocessable_entity and return
    end

    # Create tags if present in request and if "new" or use existing tags.
    if event_params[:tags].present?
      event_params[:tags].each do |tag|
        _tag = Tag.where('lower(name) = ?', tag['name'].downcase).first
        if _tag.nil?
          _tag = Tag.new(tag)
          if !_tag.save
            render json: { errors: _tag.errors.messages }, status: :unprocessable_entity and return
          end
        end
        event.tags << _tag # Add tag to the event
      end
    end

    # Create position if new or use existing position.
    position = Position.where(event_params[:position])[0]
    if position.nil?
      position = Position.new(event_params[:position])
      if !position.save
        render json: { errors: position.errors.messages }, status: :unprocessable_entity and return
      end
    end

    event.position = position
    event.creator = @current_creator

    # Do try and save the event
    if event.save
      render json: { action: 'create', event: event, position: event.position, tags: event.tags }, status: :created
    else
      render json: { errors: event.errors.messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/events/:id
  # Only able to delete the creators own events and not others.
  # Destroy associated resources aswell if relevant
  def destroy
    event = @current_creator.events.find_by_id(params[:id])
    if !event.nil?
      position = event.position
      if position.events.size == 1
        position.destroy
      end
      event.tags.each do |tag|
        if tag.events.size == 1
          tag.destroy
        end
      end
      event.destroy
      head :no_content
    else
      render json: { error: 'Event was not found. Aborted action.' }, status: :not_found
    end
  end

  # PUT /api/v1/events/:id
  # Tried to do the hash update, couldn't get it to work...
  def update
    begin
      eventParams = event_params
    rescue
      # Friendly error response, should contain event obj.
      render json: event_param_error_response, status: :unprocessable_entity and return
    end
    if !event = Event.find_by_id(params[:id])
      render json: { errors: 'Event was not found. Aborted action. Correct Id?' }, status: :not_found and return
    end

    # Process position. DRY, I know.
    # Can refactor this and tags below but i lose the response for error message.
    # Couldnt work around render json: ... "and return"
    position = Position.where(event_params[:position])[0]
    if position.nil?
      position = Position.new(event_params[:position])
      if !position.save
        render json: { errors: position.errors.messages }, status: :unprocessable_entity and return
      end
    end
    # Process tags, DRY
    tags = []
    if event_params[:tags].present?
      event_params[:tags].each do |tag|
        _tag = Tag.where('lower(name) = ?', tag['name'].downcase).first
        if _tag.nil?
          _tag = Tag.new(tag)
          if !_tag.save
            render json: { errors: _tag.errors.messages }, status: :unprocessable_entity and return
          end
        end
        tags.push(_tag)
      end
    end

    # Update event
    if !event.update(name: event_params[:name], description: event_params[:description])
      render json: { errors: event.errors.messages }, status: :unprocessable_entity and return
    end
    # Update position
    if !event.update(position: position)
      render json: { errors: event.position.errors.messages }, status: :unprocessable_entity and return
    end
    # Update tags
    if !event.update(tags: tags)
      render json: { errors: event.errors.messages }, status: :unprocessable_entity
    else
      render json: { action: 'update', event: event, position: event.position, tags: event.tags }, status: :created
    end
  end

  private
  def event_params
    params.require(:event).permit(:name, :description, tags: [:name], position: [:longitude, :latitude])
  end

  def event_param_error_response
    return {
      error: 'Parse error: check spelling, etc. Event obj required.',
      event: {
        name: 'string, required',
        description: 'string, required',
        position: { latitude: 'integer, required', longitude: 'integer, required'},
        tags: [ { name: 'optional' }, { name: 'optional' } ]
      },
    }
  end
end
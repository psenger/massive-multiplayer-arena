defmodule MassiveMultiplayerArena.Spectator.StreamManager do
  @moduledoc """
  Manages broadcast streaming for spectator mode with multiple stream formats
  and quality levels.
  """

  use GenServer
  alias MassiveMultiplayerArena.Spectator.SpectatorRoom
  require Logger

  @stream_formats [:hls, :webrtc, :dash]
  @quality_levels [:low, :medium, :high, :ultra]

  defstruct [
    :game_id,
    :streams,
    :active_viewers,
    :encoder_config,
    :bitrate_config,
    :buffer_size
  ]

  # Client API

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def start_stream(game_id, format, quality \\ :medium) do
    GenServer.call(via_tuple(game_id), {:start_stream, format, quality})
  end

  def stop_stream(game_id, stream_id) do
    GenServer.call(via_tuple(game_id), {:stop_stream, stream_id})
  end

  def add_viewer(game_id, viewer_id, stream_id) do
    GenServer.cast(via_tuple(game_id), {:add_viewer, viewer_id, stream_id})
  end

  def remove_viewer(game_id, viewer_id) do
    GenServer.cast(via_tuple(game_id), {:remove_viewer, viewer_id})
  end

  def get_stream_info(game_id) do
    GenServer.call(via_tuple(game_id), :get_stream_info)
  end

  def broadcast_game_data(game_id, game_data) do
    GenServer.cast(via_tuple(game_id), {:broadcast_game_data, game_data})
  end

  # Server Implementation

  def init(game_id) do
    state = %__MODULE__{
      game_id: game_id,
      streams: %{},
      active_viewers: %{},
      encoder_config: default_encoder_config(),
      bitrate_config: default_bitrate_config(),
      buffer_size: 5000
    }

    Logger.info("Stream manager started for game: #{game_id}")
    {:ok, state}
  end

  def handle_call({:start_stream, format, quality}, _from, state) do
    if format in @stream_formats and quality in @quality_levels do
      stream_id = generate_stream_id()
      stream_config = build_stream_config(format, quality, state.encoder_config)
      
      new_stream = %{
        id: stream_id,
        format: format,
        quality: quality,
        config: stream_config,
        started_at: System.system_time(:millisecond),
        viewers: MapSet.new(),
        buffer: :queue.new()
      }

      updated_streams = Map.put(state.streams, stream_id, new_stream)
      new_state = %{state | streams: updated_streams}

      Logger.info("Started #{format} stream with #{quality} quality: #{stream_id}")
      {:reply, {:ok, stream_id}, new_state}
    else
      {:reply, {:error, :invalid_format_or_quality}, state}
    end
  end

  def handle_call({:stop_stream, stream_id}, _from, state) do
    case Map.get(state.streams, stream_id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}
      
      stream ->
        # Notify viewers about stream ending
        Enum.each(stream.viewers, fn viewer_id ->
          notify_viewer(viewer_id, {:stream_ended, stream_id})
        end)

        updated_streams = Map.delete(state.streams, stream_id)
        updated_viewers = remove_stream_from_viewers(state.active_viewers, stream_id)
        
        new_state = %{state | streams: updated_streams, active_viewers: updated_viewers}
        
        Logger.info("Stopped stream: #{stream_id}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:get_stream_info, _from, state) do
    stream_info = Enum.map(state.streams, fn {stream_id, stream} ->
      %{
        id: stream_id,
        format: stream.format,
        quality: stream.quality,
        viewer_count: MapSet.size(stream.viewers),
        started_at: stream.started_at,
        bitrate: get_bitrate_for_quality(stream.quality, state.bitrate_config)
      }
    end)
    
    {:reply, stream_info, state}
  end

  def handle_cast({:add_viewer, viewer_id, stream_id}, state) do
    case Map.get(state.streams, stream_id) do
      nil ->
        {:noreply, state}
      
      stream ->
        updated_viewers = MapSet.put(stream.viewers, viewer_id)
        updated_stream = %{stream | viewers: updated_viewers}
        updated_streams = Map.put(state.streams, stream_id, updated_stream)
        
        updated_active_viewers = Map.put(state.active_viewers, viewer_id, stream_id)
        
        new_state = %{state | 
          streams: updated_streams,
          active_viewers: updated_active_viewers
        }
        
        Logger.debug("Added viewer #{viewer_id} to stream #{stream_id}")
        {:noreply, new_state}
    end
  end

  def handle_cast({:remove_viewer, viewer_id}, state) do
    case Map.get(state.active_viewers, viewer_id) do
      nil ->
        {:noreply, state}
      
      stream_id ->
        stream = Map.get(state.streams, stream_id)
        updated_viewers = MapSet.delete(stream.viewers, viewer_id)
        updated_stream = %{stream | viewers: updated_viewers}
        updated_streams = Map.put(state.streams, stream_id, updated_stream)
        
        updated_active_viewers = Map.delete(state.active_viewers, viewer_id)
        
        new_state = %{state | 
          streams: updated_streams,
          active_viewers: updated_active_viewers
        }
        
        Logger.debug("Removed viewer #{viewer_id} from stream #{stream_id}")
        {:noreply, new_state}
    end
  end

  def handle_cast({:broadcast_game_data, game_data}, state) do
    encoded_data = encode_game_data(game_data)
    
    updated_streams = Enum.reduce(state.streams, %{}, fn {stream_id, stream}, acc ->
      # Add data to stream buffer
      updated_buffer = add_to_buffer(stream.buffer, encoded_data, state.buffer_size)
      updated_stream = %{stream | buffer: updated_buffer}
      
      # Broadcast to all viewers of this stream
      broadcast_to_stream_viewers(stream, encoded_data)
      
      Map.put(acc, stream_id, updated_stream)
    end)
    
    new_state = %{state | streams: updated_streams}
    {:noreply, new_state}
  end

  # Private Functions

  defp via_tuple(game_id) do
    {:via, Registry, {MassiveMultiplayerArena.Registry, {__MODULE__, game_id}}}
  end

  defp generate_stream_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp default_encoder_config do
    %{
      video_codec: "h264",
      audio_codec: "aac",
      keyframe_interval: 2000,
      segment_duration: 4000
    }
  end

  defp default_bitrate_config do
    %{
      low: %{video: 500_000, audio: 64_000},
      medium: %{video: 1_500_000, audio: 128_000},
      high: %{video: 3_000_000, audio: 192_000},
      ultra: %{video: 6_000_000, audio: 256_000}
    }
  end

  defp build_stream_config(format, quality, encoder_config) do
    base_config = encoder_config
    bitrates = get_bitrate_for_quality(quality, default_bitrate_config())
    
    Map.merge(base_config, %{
      format: format,
      quality: quality,
      video_bitrate: bitrates.video,
      audio_bitrate: bitrates.audio
    })
  end

  defp get_bitrate_for_quality(quality, bitrate_config) do
    Map.get(bitrate_config, quality)
  end

  defp encode_game_data(game_data) do
    # Compress and encode game state for streaming
    game_data
    |> Jason.encode!()
    |> :zlib.compress()
  end

  defp add_to_buffer(buffer, data, max_size) do
    new_buffer = :queue.in(data, buffer)
    
    if :queue.len(new_buffer) > max_size do
      {_dropped, trimmed_buffer} = :queue.out(new_buffer)
      trimmed_buffer
    else
      new_buffer
    end
  end

  defp broadcast_to_stream_viewers(stream, data) do
    Enum.each(stream.viewers, fn viewer_id ->
      send_to_viewer(viewer_id, data, stream.format)
    end)
  end

  defp send_to_viewer(viewer_id, data, format) do
    # Send data to viewer based on stream format
    case format do
      :hls ->
        # Send HLS segments
        SpectatorRoom.send_hls_segment(viewer_id, data)
      
      :webrtc ->
        # Send WebRTC data
        SpectatorRoom.send_webrtc_data(viewer_id, data)
      
      :dash ->
        # Send DASH segments
        SpectatorRoom.send_dash_segment(viewer_id, data)
    end
  rescue
    error ->
      Logger.warn("Failed to send data to viewer #{viewer_id}: #{inspect(error)}")
  end

  defp notify_viewer(viewer_id, message) do
    SpectatorRoom.notify_viewer(viewer_id, message)
  rescue
    error ->
      Logger.warn("Failed to notify viewer #{viewer_id}: #{inspect(error)}")
  end

  defp remove_stream_from_viewers(active_viewers, stream_id) do
    Enum.reduce(active_viewers, %{}, fn {viewer_id, current_stream_id}, acc ->
      if current_stream_id == stream_id do
        acc
      else
        Map.put(acc, viewer_id, current_stream_id)
      end
    end)
  end
end
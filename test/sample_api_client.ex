defmodule SampleAPIClient do
  @moduledoc """
  Sample API client demonstrating usage of VCUtils.HTTPClient with JSONPlaceholder public API.
  This module shows how to implement a real HTTP client that can be used in tests.
  """
  use VCUtils.HTTPClient

  @base_url "https://jsonplaceholder.typicode.com"

  # ----- Callbacks ----- #

  @impl true
  def auth_headers do
    [
      {"Content-Type", "application/json"},
      {"User-Agent", "VCUtils-Sample-Client/1.0"}
    ]
  end

  # ----- End of Callbacks ----- #

  @doc """
  Fetches all posts from JSONPlaceholder API
  """
  def get_posts do
    request(:get, "#{@base_url}/posts", nil, auth_headers())
  end

  @doc """
  Fetches a specific post by ID
  """
  def get_post(id) when is_integer(id) do
    request(:get, "#{@base_url}/posts/#{id}", nil, auth_headers())
  end

  @doc """
  Creates a new post
  """
  def create_post(post_data) when is_map(post_data) do
    request(:post, "#{@base_url}/posts", post_data, auth_headers())
  end

  @doc """
  Updates an existing post
  """
  def update_post(id, post_data) when is_integer(id) and is_map(post_data) do
    request(:put, "#{@base_url}/posts/#{id}", post_data, auth_headers())
  end

  @doc """
  Deletes a post by ID
  """
  def delete_post(id) when is_integer(id) do
    request(:delete, "#{@base_url}/posts/#{id}", nil, auth_headers())
  end

  @doc """
  Fetches all users
  """
  def get_users do
    request(:get, "#{@base_url}/users", nil, auth_headers())
  end

  @doc """
  Fetches a specific user by ID
  """
  def get_user(id) when is_integer(id) do
    request(:get, "#{@base_url}/users/#{id}", nil, auth_headers())
  end

  @doc """
  Fetches comments for a specific post
  """
  def get_post_comments(post_id) when is_integer(post_id) do
    request(:get, "#{@base_url}/posts/#{post_id}/comments", nil, auth_headers())
  end

  @doc """
  Fetches all albums
  """
  def get_albums do
    request(:get, "#{@base_url}/albums", nil, auth_headers())
  end

  @doc """
  Demonstrates error handling with invalid endpoint
  """
  def get_invalid_endpoint do
    request(:get, "#{@base_url}/invalid-endpoint", nil, auth_headers())
  end

  @doc """
  Test bypass decoding for no context or empty responses
  """
  def empty_response do
    url = "https://httpbin.org/status/204"
    request(:get, url, nil, auth_headers())
  end
end

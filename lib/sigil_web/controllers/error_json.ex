defmodule SigilWeb.ErrorJSON do
  @moduledoc """
  JSON error rendering for Sigil.

  Renders error responses as JSON for API endpoints.
  """

  @doc """
  Renders a JSON error response based on the template name.

  Returns a map with an `errors` key containing a detail message
  derived from the HTTP status code.
  """
  @spec render(String.t(), map()) :: map()
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

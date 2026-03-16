defmodule SigilWeb.ErrorHTML do
  @moduledoc """
  HTML error rendering for Sigil.

  Renders error responses as plain text for browser requests,
  derived from the HTTP status code.
  """

  use SigilWeb, :html

  @doc """
  Renders an HTML error response based on the template name.

  The default implementation renders a plain text message
  derived from the status code in the template name.
  """
  @spec render(String.t(), map()) :: String.t()
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

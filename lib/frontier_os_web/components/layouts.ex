defmodule FrontierOSWeb.Layouts do
  @moduledoc """
  Layout components for FrontierOS.

  Embeds root and app layout templates used by the
  endpoint and LiveView rendering pipeline.
  """

  use FrontierOSWeb, :html

  embed_templates "layouts/*"
end

defmodule FrontierOSWeb.LandingLive do
  @moduledoc """
  Landing page for FrontierOS.

  Serves as a minimal verification that the LiveView stack
  is fully operational.
  """

  use FrontierOSWeb, :live_view

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Home")}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center min-h-[60vh]">
      <div class="text-center">
        <h1 class="text-4xl font-bold text-gray-100">FrontierOS</h1>
        <p class="mt-4 text-lg text-gray-400">System Online</p>
      </div>
    </div>
    """
  end
end

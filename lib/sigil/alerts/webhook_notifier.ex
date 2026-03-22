defmodule Sigil.Alerts.WebhookNotifier do
  @moduledoc """
  Behaviour for delivering persisted alerts to external webhook providers.
  """

  alias Sigil.Alerts.{Alert, WebhookConfig}

  @typedoc "Options accepted by webhook notifier implementations."
  @type option() :: {:req_options, keyword()} | {:delay_fun, (non_neg_integer() -> term())}

  @type options() :: [option()]

  @doc "Delivers an alert notification to the configured webhook destination."
  @callback deliver(Alert.t(), WebhookConfig.t(), options()) ::
              :ok
              | {:error, {:webhook_failed, pos_integer()}}
              | {:error, {:network_error, term()}}
end

defmodule Sigil.TestSupport.BlobAvailableClient do
  @moduledoc false

  def blob_exists?(_blob_id, _opts), do: true
end

defmodule Sigil.TestSupport.BlobMissingClient do
  @moduledoc false

  def blob_exists?(_blob_id, _opts), do: false
end

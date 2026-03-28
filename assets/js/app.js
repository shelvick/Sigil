import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

import FuelCountdown from "./hooks/fuel_countdown"
import InfiniteScroll from "./hooks/infinite_scroll"
import WalletConnect from "./hooks/wallet_hook"
import SealEncrypt from "./hooks/seal_hook"
import PseudonymKey from "./hooks/pseudonym_hook"

let Hooks = {
  FuelCountdown: FuelCountdown,
  InfiniteScroll: InfiniteScroll,
  WalletConnect: WalletConnect,
  SealEncrypt: SealEncrypt,
  PseudonymKey: PseudonymKey
}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()

window.liveSocket = liveSocket

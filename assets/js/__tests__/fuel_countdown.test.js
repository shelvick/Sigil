import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { mountHook } from "./support/liveview_hook"
import FuelCountdown from "../hooks/fuel_countdown"

describe("FuelCountdown hook", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date("2042-01-01T00:00:00Z"))
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it("renders a live countdown from data-depletes-at", () => {
    const { hook, destroy } = mountHook(FuelCountdown, {
      dataset: { depletesAt: "2042-01-01T01:00:00Z" }
    })

    expect(hook.el.textContent).toBe("in 1h 0m 0s")

    vi.advanceTimersByTime(10_000)

    expect(hook.el.textContent).toBe("in 0h 59m 50s")

    destroy()
  })

  it("shows Depleted when remaining time reaches zero", () => {
    const { hook, destroy } = mountHook(FuelCountdown, {
      dataset: { depletesAt: "2042-01-01T00:00:01Z" }
    })

    expect(hook.el.textContent).toBe("in 0h 0m 1s")

    vi.advanceTimersByTime(1_000)

    expect(hook.el.textContent).toBe("Depleted")

    destroy()
  })

  it("restarts countdown when updated with a new timestamp", () => {
    const { hook, destroy } = mountHook(FuelCountdown, {
      dataset: { depletesAt: "2042-01-01T00:10:00Z" }
    })

    expect(hook.el.textContent).toBe("in 0h 10m 0s")

    hook.el.dataset.depletesAt = "2042-01-01T00:20:00Z"
    hook.updated()

    expect(hook.el.textContent).toBe("in 0h 20m 0s")

    destroy()
  })

  it("clears the interval when destroyed", () => {
    const clearSpy = vi.spyOn(window, "clearInterval")

    const { destroy } = mountHook(FuelCountdown, {
      dataset: { depletesAt: "2042-01-01T01:00:00Z" }
    })

    destroy()

    expect(clearSpy).toHaveBeenCalled()
  })
})

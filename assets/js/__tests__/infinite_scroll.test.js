import { describe, it, expect, vi, afterEach } from "vitest"
import { mountHook } from "./support/liveview_hook"
import InfiniteScroll from "../hooks/infinite_scroll"

class MockIntersectionObserver {
  static instances = []

  constructor(callback) {
    this.callback = callback
    this.observe = vi.fn()
    this.disconnect = vi.fn()
    MockIntersectionObserver.instances.push(this)
  }

  trigger(entries) {
    this.callback(entries)
  }
}

describe("InfiniteScroll hook", () => {
  afterEach(() => {
    MockIntersectionObserver.instances = []
    vi.unstubAllGlobals()
  })

  it("pushes load_more when the sentinel enters the viewport", () => {
    vi.stubGlobal("IntersectionObserver", MockIntersectionObserver)

    const { events, destroy } = mountHook(InfiniteScroll, {
      id: "alerts-feed-sentinel",
      dataset: { hasMore: "true" }
    })

    const observer = MockIntersectionObserver.instances[0]
    expect(observer.observe).toHaveBeenCalled()

    observer.trigger([{ isIntersecting: true }])

    expect(events).toEqual([{ event: "load_more", payload: {} }])

    destroy()
  })

  it("does not push load_more when the feed is exhausted", () => {
    vi.stubGlobal("IntersectionObserver", MockIntersectionObserver)

    const { events, destroy } = mountHook(InfiniteScroll, {
      id: "alerts-feed-sentinel",
      dataset: { hasMore: "false" }
    })

    expect(MockIntersectionObserver.instances).toHaveLength(0)
    expect(events).toEqual([])

    destroy()
  })

  it("resets after updated so later intersections can request another page", () => {
    vi.stubGlobal("IntersectionObserver", MockIntersectionObserver)

    const { hook, events, destroy } = mountHook(InfiniteScroll, {
      id: "alerts-feed-sentinel",
      dataset: { hasMore: "true" }
    })

    let observer = MockIntersectionObserver.instances[0]
    observer.trigger([{ isIntersecting: true }])
    observer.trigger([{ isIntersecting: true }])

    expect(events).toHaveLength(1)

    hook.updated()

    observer = MockIntersectionObserver.instances[1]
    observer.trigger([{ isIntersecting: true }])

    expect(events).toHaveLength(2)

    destroy()
  })

  it("disconnects the observer when destroyed", () => {
    vi.stubGlobal("IntersectionObserver", MockIntersectionObserver)

    const { destroy } = mountHook(InfiniteScroll, {
      id: "alerts-feed-sentinel",
      dataset: { hasMore: "true" }
    })

    const observer = MockIntersectionObserver.instances[0]
    destroy()

    expect(observer.disconnect).toHaveBeenCalled()
  })
})

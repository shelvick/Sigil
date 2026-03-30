import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { mountHook } from "./support/liveview_hook"

const threeState = {
  intersections: [],
  rendererShouldThrow: false
}

vi.mock("three", () => {
  class Scene {
    constructor() {
      this.children = []
    }

    add(object) {
      this.children.push(object)
    }

    remove(object) {
      this.children = this.children.filter((entry) => entry !== object)
    }
  }

  class PerspectiveCamera {
    constructor(fov = 60, aspect = 1, near = 0.1, far = 5_000) {
      this.fov = fov
      this.aspect = aspect
      this.near = near
      this.far = far
      this.position = {
        x: 0,
        y: 0,
        z: 0,
        set: (x, y, z) => {
          this.position.x = x
          this.position.y = y
          this.position.z = z
        },
        distanceTo: (target) => {
          const dx = this.position.x - target.x
          const dy = this.position.y - target.y
          const dz = this.position.z - target.z
          return Math.sqrt(dx * dx + dy * dy + dz * dz)
        },
        clone: () => ({ x: this.position.x, y: this.position.y, z: this.position.z }),
        length: () => Math.sqrt(this.position.x ** 2 + this.position.y ** 2 + this.position.z ** 2)
      }
      this.lookAtTarget = { x: 0, y: 0, z: 0 }
    }

    lookAt(x, y, z) {
      this.lookAtTarget = { x, y, z }
    }

    updateProjectionMatrix() {
      return undefined
    }
  }

  class WebGLRenderer {
    constructor() {
      if (threeState.rendererShouldThrow) {
        throw new Error("WebGL unavailable")
      }

      this.domElement = document.createElement("canvas")
      this.domElement.getBoundingClientRect = () => ({
        left: 0,
        top: 0,
        width: 800,
        height: 600
      })
    }

    setPixelRatio() {
      return undefined
    }

    setSize() {
      return undefined
    }

    render() {
      return undefined
    }

    dispose() {
      return undefined
    }
  }

  class BufferGeometry {
    constructor() {
      this.attributes = {}
      this.disposed = false
    }

    setAttribute(name, value) {
      this.attributes[name] = value
    }

    getAttribute(name) {
      return this.attributes[name]
    }

    dispose() {
      this.disposed = true
      return undefined
    }
  }

  class Float32BufferAttribute {
    constructor(array, itemSize) {
      this.array = array
      this.itemSize = itemSize
    }
  }

  class PointsMaterial {
    constructor(options = {}) {
      this.options = options
      this.visible = true
    }

    dispose() {
      return undefined
    }
  }

  class Points {
    constructor(geometry, material) {
      this.geometry = geometry
      this.material = material
      this.visible = true
    }
  }

  class Raycaster {
    constructor() {
      this.params = { Points: { threshold: 0 } }
    }

    setFromCamera() {
      return undefined
    }

    intersectObject() {
      return threeState.intersections
    }
  }

  class Vector2 {
    constructor(x = 0, y = 0) {
      this.x = x
      this.y = y
    }
  }

  class CanvasTexture {
    constructor(canvas) {
      this.canvas = canvas
      this.needsUpdate = false
    }

    dispose() {
      return undefined
    }
  }

  class Color {
    constructor(value) {
      this.value = value
    }
  }

  return {
    Scene,
    PerspectiveCamera,
    WebGLRenderer,
    BufferGeometry,
    Float32BufferAttribute,
    PointsMaterial,
    Points,
    Raycaster,
    Vector2,
    CanvasTexture,
    Color
  }
})

vi.mock("three/addons/controls/OrbitControls.js", () => {
  class OrbitControls {
    constructor(_camera, _domElement) {
      this.target = {
        x: 0,
        y: 0,
        z: 0,
        set: (x, y, z) => {
          this.target.x = x
          this.target.y = y
          this.target.z = z
        },
        clone: () => ({ x: this.target.x, y: this.target.y, z: this.target.z })
      }
    }

    update() {
      return undefined
    }

    dispose() {
      return undefined
    }
  }

  return { OrbitControls }
})

async function loadUtils() {
  return import("../hooks/galaxy_map_utils")
}

async function loadHook() {
  const module = await import("../hooks/galaxy_map")
  return module.default
}

describe("galaxy_map_utils", () => {
  it("normalizeCoordinates centers and scales positions", async () => {
    const { normalizeCoordinates } = await loadUtils()

    const systems = [
      { id: 1, x: -120, y: 50, z: -300 },
      { id: 2, x: 900, y: 140, z: 250 }
    ]

    const result = normalizeCoordinates(systems, 500)
    const values = Array.from(result.positions)

    expect(values).toHaveLength(6)
    expect(Math.max(...values.map((value) => Math.abs(value)))).toBeLessThanOrEqual(500)
    expect((values[0] + values[3]) / 2).toBeCloseTo(0, 4)
    expect((values[1] + values[4]) / 2).toBeCloseTo(0, 4)
    expect((values[2] + values[5]) / 2).toBeCloseTo(0, 4)
  })

  it("normalizeCoordinates places single system at origin", async () => {
    const { normalizeCoordinates } = await loadUtils()

    const result = normalizeCoordinates([{ id: 1, x: 12, y: -34, z: 56 }], 500)

    expect(Array.from(result.positions)).toEqual([0, 0, 0])
  })

  it("normalizeCoordinates preserves relative distances", async () => {
    const { normalizeCoordinates } = await loadUtils()

    const systems = [
      { id: 1, x: 0, y: 0, z: 0 },
      { id: 2, x: 10, y: 0, z: 0 },
      { id: 3, x: 0, y: 20, z: 0 }
    ]

    const result = normalizeCoordinates(systems, 500)
    const [x1, y1, z1, x2, y2, z2, x3, y3, z3] = Array.from(result.positions)

    const rawAB = 10
    const rawAC = 20
    const normalizedAB = Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2 + (z2 - z1) ** 2)
    const normalizedAC = Math.sqrt((x3 - x1) ** 2 + (y3 - y1) ** 2 + (z3 - z1) ** 2)

    expect(normalizedAB / normalizedAC).toBeCloseTo(rawAB / rawAC, 4)
  })

  it("buildSystemIndex maps all system IDs correctly", async () => {
    const { buildSystemIndex } = await loadUtils()

    const systems = [{ id: 30_000_001 }, { id: 30_000_142 }, { id: 30_000_900 }]
    const index = buildSystemIndex(systems)

    expect(index.get(30_000_001)).toBe(0)
    expect(index.get(30_000_142)).toBe(1)
    expect(index.get(30_000_900)).toBe(2)
  })

  it("normalizeWithTransform uses provided offset and scale", async () => {
    const { normalizeWithTransform } = await loadUtils()

    const systems = [{ x: 20, y: 35, z: 40 }]
    const positions = normalizeWithTransform(systems, {
      offset: { x: 10, y: 20, z: 30 },
      scale: 2
    })

    expect(Array.from(positions)).toEqual([20, 30, 20])
  })

  it("buildOverlayPositions resolves known IDs and skips unknown", async () => {
    const { buildOverlayPositions } = await loadUtils()

    const systemIndex = new Map([
      [30_000_001, 0],
      [30_000_142, 1]
    ])

    const positions = new Float32Array([
      10,
      11,
      12,
      20,
      21,
      22
    ])

    const result = buildOverlayPositions([30_000_142, 99_999_999, 30_000_001], systemIndex, positions)

    expect(result.systemIds).toEqual([30_000_142, 30_000_001])
    expect(Array.from(result.positions)).toEqual([20, 21, 22, 10, 11, 12])
  })

  it("resolveSystemId returns correct system ID from index", async () => {
    const { resolveSystemId } = await loadUtils()

    const systemIds = [30_000_001, 30_000_142, 30_000_900]

    expect(resolveSystemId(1, systemIds)).toBe(30_000_142)
  })

  it("createDefaultCamera positions camera above scene looking down", async () => {
    const { createDefaultCamera } = await loadUtils()

    const camera = createDefaultCamera(500)

    expect(camera.position.y).toBeGreaterThan(0)
    expect(camera.position.x).toBe(0)
    expect(camera.position.z).toBe(0)
    expect(camera.lookAtTarget).toEqual({ x: 0, y: 0, z: 0 })
  })

  it("shouldShowConstellations toggles at distance threshold", async () => {
    const { shouldShowConstellations } = await loadUtils()

    expect(shouldShowConstellations(501, 500)).toBe(true)
    expect(shouldShowConstellations(500, 500)).toBe(false)
    expect(shouldShowConstellations(200, 500)).toBe(false)
  })
})

describe("GalaxyMap hook", () => {
  beforeEach(() => {
    threeState.intersections = []
    threeState.rendererShouldThrow = false

    vi.stubGlobal("requestAnimationFrame", vi.fn(() => 1))
    vi.stubGlobal("cancelAnimationFrame", vi.fn())
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation(() => ({
      clearRect: () => undefined,
      beginPath: () => undefined,
      arc: () => undefined,
      fill: () => undefined,
      fillStyle: "#ffffff"
    }))
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it("GalaxyMap hook emits map_ready on mount", async () => {
    const { destroy, events } = mountHook(await loadHook(), {
      id: "galaxy-map"
    })

    expect(events).toContainEqual({ event: "map_ready", payload: {} })

    destroy()
  })

  it("GalaxyMap hook emits system_selected for clicked point", async () => {
    const { hook, destroy, events, pushServerEvent } = mountHook(await loadHook(), {
      id: "galaxy-map"
    })

    await pushServerEvent("init_systems", {
      systems: [{ id: 30_000_142, name: "Piekura", constellation_id: 200_001, x: 10, y: 20, z: 30 }]
    })

    threeState.intersections = [{ index: 0 }]

    const canvas = hook.el.querySelector("canvas")
    canvas.dispatchEvent(new MouseEvent("click", { bubbles: true, clientX: 120, clientY: 80 }))

    expect(events).toContainEqual({
      event: "system_selected",
      payload: { system_id: 30_000_142 }
    })

    destroy()
  })

  it("GalaxyMap hook emits system_deselected on empty click", async () => {
    const { hook, destroy, events } = mountHook(await loadHook(), {
      id: "galaxy-map"
    })

    threeState.intersections = []

    const canvas = hook.el.querySelector("canvas")
    canvas.dispatchEvent(new MouseEvent("click", { bubbles: true, clientX: 160, clientY: 100 }))

    expect(events).toContainEqual({ event: "system_deselected", payload: {} })

    destroy()
  })

  it("GalaxyMap hook handles select_system event", async () => {
    const { hook, destroy, events, pushServerEvent } = mountHook(await loadHook(), {
      id: "galaxy-map"
    })

    await pushServerEvent("init_systems", {
      systems: [{ id: 30_000_142, name: "Piekura", constellation_id: 200_001, x: 10, y: 20, z: 30 }]
    })

    await pushServerEvent("select_system", { system_id: 30_000_142 })

    const selectedEvents = events.filter((entry) => entry.event === "system_selected")

    expect(selectedEvents).toEqual([{ event: "system_selected", payload: { system_id: 30_000_142 } }])
    expect(hook.controls.target.clone()).toEqual({ x: 0, y: 0, z: 0 })
    expect(hook.camera.lookAtTarget).toEqual({ x: 0, y: 0, z: 0 })
    expect(hook.camera.position.y).toBeCloseTo(40, 6)
    expect(hook.selectedHighlight).toBeTruthy()
    expect(hook.selectedHighlight.material.options.size).toBe(5)

    destroy()
  })

  it("overlay visibility persists across overlay refresh", async () => {
    const { hook, destroy, pushServerEvent } = mountHook(await loadHook(), {
      id: "galaxy-map"
    })

    await pushServerEvent("init_systems", {
      systems: [{ id: 30_000_142, name: "Piekura", constellation_id: 200_001, x: 10, y: 20, z: 30 }]
    })

    await pushServerEvent("update_overlays", {
      tribe_locations: [],
      tribe_scouting: [],
      marketplace: [{ system_id: 30_000_142 }],
      overlay_toggles: { marketplace: true }
    })

    expect(hook.overlayLayers.marketplace.visible).toBe(true)

    await pushServerEvent("toggle_overlay", { layer: "marketplace", visible: false })

    expect(hook.overlayLayers.marketplace.visible).toBe(false)

    await pushServerEvent("update_overlays", {
      tribe_locations: [],
      tribe_scouting: [],
      marketplace: [{ system_id: 30_000_142 }],
      overlay_toggles: { marketplace: false }
    })

    expect(hook.overlayLayers.marketplace.visible).toBe(false)

    destroy()
  })

  it("GalaxyMap hook updates point colors from categories", async () => {
    const { hook, destroy, pushServerEvent } = mountHook(await loadHook(), {
      id: "galaxy-map"
    })

    await pushServerEvent("init_systems", {
      systems: [
        { id: 30_000_142, name: "Piekura", constellation_id: 200_001, x: 10, y: 20, z: 30 },
        { id: 30_000_900, name: "Jita", constellation_id: 200_001, x: 40, y: 50, z: 60 }
      ]
    })

    await pushServerEvent("update_system_colors", {
      categories: {
        30000142: "both",
        30000900: "fuel_critical"
      }
    })

    const colorArray = Array.from(hook.systemPoints.geometry.getAttribute("color").array)

    expect(colorArray.slice(0, 3)).toEqual([1, 1, 1])
    expect(colorArray[3]).toBeCloseTo(1, 4)
    expect(colorArray[4]).toBeCloseTo(0.2667, 4)
    expect(colorArray[5]).toBeCloseTo(0.2667, 4)

    destroy()
  })

  it("map shows WebGL fallback message when renderer unavailable", async () => {
    threeState.rendererShouldThrow = true

    const { hook, destroy } = mountHook(await loadHook(), {
      id: "galaxy-map"
    })

    try {
      expect(hook.el.textContent).toContain("WebGL required for galaxy map")
    } finally {
      destroy()
    }
  })
})

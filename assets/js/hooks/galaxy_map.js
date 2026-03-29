import * as THREE from "three"
import { OrbitControls } from "three/addons/controls/OrbitControls.js"

import {
  buildOverlayPositions,
  buildSystemIndex,
  createDefaultCamera,
  normalizeCoordinates,
  normalizeWithTransform,
  resolveSystemId,
  shouldShowConstellations
} from "./galaxy_map_utils"

const TARGET_RANGE = 500
const CLUSTER_THRESHOLD = 500
const SELECTED_POINT_SIZE = 9

const OVERLAY_CONFIG = {
  tribe_locations: { color: new THREE.Color("#00e5ff"), size: 6 },
  tribe_scouting: { color: new THREE.Color("#ffc107"), size: 5 },
  marketplace: { color: new THREE.Color("#4caf50"), size: 5 }
}

function pointMaterial(color, size) {
  return new THREE.PointsMaterial({
    color,
    size,
    sizeAttenuation: true
  })
}

const GalaxyMap = {
  mounted() {
    this.scene = null
    this.camera = null
    this.renderer = null
    this.controls = null
    this.raycaster = null
    this.pointer = new THREE.Vector2()
    this.animationId = null
    this.systemPositions = new Float32Array()
    this.systemIds = []
    this.systemIndex = new Map()
    this.systemNormalization = null
    this.constellationsRaw = []
    this.selectedSystemId = null
    this.systemPoints = null
    this.constellationPoints = null
    this.selectedHighlight = null
    this.overlayLayers = {
      tribe_locations: null,
      tribe_scouting: null,
      marketplace: null
    }
    this.overlayVisibility = {
      tribe_locations: true,
      tribe_scouting: true,
      marketplace: true
    }

    this._registerEvents()

    if (!this._initializeRenderer()) {
      return
    }

    this._bindDomEvents()
    this._startAnimationLoop()
    this.pushEvent("map_ready", {})
  },

  updated() {
    // Updates are event-driven via handleEvent callbacks.
  },

  destroyed() {
    this._unbindDomEvents()

    if (this.animationId) {
      cancelAnimationFrame(this.animationId)
      this.animationId = null
    }

    this._disposePoints(this.systemPoints)
    this.systemPoints = null

    this._disposePoints(this.constellationPoints)
    this.constellationPoints = null

    this._disposePoints(this.selectedHighlight)
    this.selectedHighlight = null

    for (const layer of Object.keys(this.overlayLayers)) {
      this._disposePoints(this.overlayLayers[layer])
      this.overlayLayers[layer] = null
    }

    if (this.controls) {
      this.controls.dispose()
      this.controls = null
    }

    if (this.renderer) {
      this.renderer.dispose()
      this.renderer = null
    }

    this.scene = null
    this.camera = null
    this.raycaster = null
  },

  _registerEvents() {
    this.handleEvent("init_systems", ({ systems } = {}) => {
      this._initSystems(systems || [])
    })

    this.handleEvent("init_constellations", ({ constellations } = {}) => {
      this._initConstellations(constellations || [])
    })

    this.handleEvent("update_overlays", (payload = {}) => {
      this._updateOverlays(payload)
    })

    this.handleEvent("toggle_overlay", ({ layer, visible } = {}) => {
      this._setOverlayVisibility(layer, visible)
    })

    this.handleEvent("select_system", ({ system_id: systemId } = {}) => {
      const index = this.systemIndex.get(systemId)
      if (index === undefined) {
        return
      }

      this.selectedSystemId = systemId
      this._highlightSystemByIndex(index)
      this._focusSystemByIndex(index)
      this.pushEvent("system_selected", { system_id: systemId })
    })
  },

  _initializeRenderer() {
    try {
      this.scene = new THREE.Scene()
      this.camera = createDefaultCamera(TARGET_RANGE)
      this.camera.aspect = this._aspect()
      this.camera.updateProjectionMatrix()

      this.renderer = new THREE.WebGLRenderer({ antialias: true })
      this.renderer.setPixelRatio(window.devicePixelRatio || 1)

      this.el.replaceChildren(this.renderer.domElement)
      this._resizeRenderer()

      this.controls = new OrbitControls(this.camera, this.renderer.domElement)
      this.controls.target.set(0, 0, 0)
      this.controls.update()

      this.raycaster = new THREE.Raycaster()
      this.raycaster.params.Points.threshold = 12

      return true
    } catch (_error) {
      this._showWebglFallback()
      return false
    }
  },

  _showWebglFallback() {
    this.el.textContent = "WebGL required for galaxy map"
  },

  _bindDomEvents() {
    if (!this.renderer) {
      return
    }

    this._onCanvasClick = (event) => this._handleClick(event)
    this.renderer.domElement.addEventListener("click", this._onCanvasClick)

    this._onResize = () => this._resizeRenderer()
    window.addEventListener("resize", this._onResize)
  },

  _unbindDomEvents() {
    if (this.renderer?.domElement && this._onCanvasClick) {
      this.renderer.domElement.removeEventListener("click", this._onCanvasClick)
      this._onCanvasClick = null
    }

    if (this._onResize) {
      window.removeEventListener("resize", this._onResize)
      this._onResize = null
    }
  },

  _startAnimationLoop() {
    const animate = () => {
      this.animationId = requestAnimationFrame(animate)
      this.controls?.update()
      this._updateZoomDependentVisibility()
      this.renderer?.render(this.scene, this.camera)
    }

    this.animationId = requestAnimationFrame(animate)
  },

  _updateZoomDependentVisibility() {
    if (!this.camera || !this.controls || !this.constellationPoints || !this.systemPoints) {
      return
    }

    const distance = this.camera.position.distanceTo(this.controls.target)
    const showConstellations = shouldShowConstellations(distance, CLUSTER_THRESHOLD)

    this.constellationPoints.visible = showConstellations
    this.systemPoints.visible = !showConstellations
  },

  _resizeRenderer() {
    if (!this.renderer || !this.camera) {
      return
    }

    const width = this.el.clientWidth || 800
    const height = this.el.clientHeight || 600

    this.renderer.setSize(width, height)
    this.camera.aspect = width / Math.max(height, 1)
    this.camera.updateProjectionMatrix()
  },

  _aspect() {
    const width = this.el.clientWidth || 800
    const height = this.el.clientHeight || 600
    return width / Math.max(height, 1)
  },

  _initSystems(systems) {
    const normalization = normalizeCoordinates(systems, TARGET_RANGE)
    const positions = normalization.positions

    this.systemPositions = positions
    this.systemNormalization = {
      offset: normalization.offset,
      scale: normalization.scale
    }
    this.systemIds = systems.map((system) => system.id)
    this.systemIndex = buildSystemIndex(systems)

    this._disposePoints(this.systemPoints)

    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3))

    const material = pointMaterial(new THREE.Color("#8899bb"), 3)
    this.systemPoints = new THREE.Points(geometry, material)
    this.scene?.add(this.systemPoints)

    // Constellations share the same transform as systems to avoid frame mismatches.
    this._rebuildConstellationPoints()

    if (this.selectedSystemId !== null) {
      const selectedIndex = this.systemIndex.get(this.selectedSystemId)
      if (selectedIndex !== undefined) {
        this._highlightSystemByIndex(selectedIndex)
      } else {
        this._clearHighlight()
      }
    }
  },

  _initConstellations(constellations) {
    this.constellationsRaw = Array.isArray(constellations) ? constellations : []
    this._rebuildConstellationPoints()
  },

  _rebuildConstellationPoints() {
    this._disposePoints(this.constellationPoints)
    this.constellationPoints = null

    if (!this.constellationsRaw.length || !this.systemNormalization) {
      return
    }

    const positions = normalizeWithTransform(this.constellationsRaw, this.systemNormalization)

    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3))

    const material = pointMaterial(new THREE.Color("#9fb7ff"), 7)
    this.constellationPoints = new THREE.Points(geometry, material)
    this.constellationPoints.visible = false

    this.scene?.add(this.constellationPoints)
  },

  _updateOverlays({
    tribe_locations: tribeLocations = [],
    tribe_scouting: tribeScouting = [],
    marketplace = [],
    overlay_toggles: overlayToggles = null
  } = {}) {
    if (overlayToggles && typeof overlayToggles === "object") {
      for (const [layer, visible] of Object.entries(overlayToggles)) {
        if (Object.hasOwn(this.overlayVisibility, layer)) {
          this.overlayVisibility[layer] = Boolean(visible)
        }
      }
    }

    const layers = {
      tribe_locations: tribeLocations,
      tribe_scouting: tribeScouting,
      marketplace
    }

    for (const [layer, entries] of Object.entries(layers)) {
      const ids = entries
        .map((entry) => entry?.system_id)
        .filter((systemId) => Number.isInteger(systemId))

      const { positions } = buildOverlayPositions(ids, this.systemIndex, this.systemPositions)
      this._replaceOverlayLayer(layer, positions)
    }
  },

  _replaceOverlayLayer(layer, positions) {
    this._disposePoints(this.overlayLayers[layer])

    if (!positions.length) {
      this.overlayLayers[layer] = null
      return
    }

    const config = OVERLAY_CONFIG[layer]
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3))

    const material = pointMaterial(config.color, config.size)
    const points = new THREE.Points(geometry, material)
    points.visible = this.overlayVisibility[layer] !== false

    this.overlayLayers[layer] = points
    this.scene?.add(points)
  },

  _setOverlayVisibility(layer, visible) {
    if (!Object.hasOwn(this.overlayVisibility, layer)) {
      return
    }

    const normalizedVisible = Boolean(visible)
    this.overlayVisibility[layer] = normalizedVisible

    if (this.overlayLayers[layer]) {
      this.overlayLayers[layer].visible = normalizedVisible
    }
  },

  _handleClick(event) {
    if (!this.raycaster || !this.camera || !this.systemPoints || !this.renderer) {
      this._clearHighlight()
      this.pushEvent("system_deselected", {})
      return
    }

    const rect = this.renderer.domElement.getBoundingClientRect()
    const width = rect.width || 1
    const height = rect.height || 1

    this.pointer.x = ((event.clientX - rect.left) / width) * 2 - 1
    this.pointer.y = -((event.clientY - rect.top) / height) * 2 + 1

    this.raycaster.setFromCamera(this.pointer, this.camera)
    const [intersection] = this.raycaster.intersectObject(this.systemPoints)

    const systemId = resolveSystemId(intersection?.index, this.systemIds)

    if (systemId !== null) {
      this.selectedSystemId = systemId
      const selectedIndex = this.systemIndex.get(systemId)
      if (selectedIndex !== undefined) {
        this._highlightSystemByIndex(selectedIndex)
      }
      this.pushEvent("system_selected", { system_id: systemId })
      return
    }

    this.selectedSystemId = null
    this._clearHighlight()
    this.pushEvent("system_deselected", {})
  },

  _systemPositionAt(index) {
    const base = index * 3
    if (base < 0 || base + 2 >= this.systemPositions.length) {
      return null
    }

    return {
      x: this.systemPositions[base],
      y: this.systemPositions[base + 1],
      z: this.systemPositions[base + 2]
    }
  },

  _focusSystemByIndex(index) {
    const point = this._systemPositionAt(index)
    if (!point || !this.camera || !this.controls) {
      return
    }

    const currentTarget = this.controls.target || { x: 0, y: 0, z: 0 }
    const deltaX = this.camera.position.x - currentTarget.x
    const deltaY = this.camera.position.y - currentTarget.y
    const deltaZ = this.camera.position.z - currentTarget.z

    const currentDistance = Math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)
    const safeDistance = currentDistance > 0 ? currentDistance : TARGET_RANGE * 1.6
    const zoomDistance = Math.max(40, safeDistance * 0.6)
    const norm = safeDistance > 0 ? safeDistance : 1

    this.controls.target.set(point.x, point.y, point.z)
    this.camera.position.set(
      point.x + (deltaX / norm) * zoomDistance,
      point.y + (deltaY / norm) * zoomDistance,
      point.z + (deltaZ / norm) * zoomDistance
    )
    this.camera.lookAt(point.x, point.y, point.z)
    this.controls.update()
  },

  _highlightSystemByIndex(index) {
    const point = this._systemPositionAt(index)
    if (!point) {
      this._clearHighlight()
      return
    }

    this._clearHighlight()

    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute(
      "position",
      new THREE.Float32BufferAttribute(new Float32Array([point.x, point.y, point.z]), 3)
    )

    const material = pointMaterial(new THREE.Color("#ffffff"), SELECTED_POINT_SIZE)
    this.selectedHighlight = new THREE.Points(geometry, material)
    this.scene?.add(this.selectedHighlight)
  },

  _clearHighlight() {
    this._disposePoints(this.selectedHighlight)
    this.selectedHighlight = null
  },

  _disposePoints(points) {
    if (!points) {
      return
    }

    this.scene?.remove(points)
    points.geometry?.dispose?.()
    points.material?.dispose?.()
  }
}

export default GalaxyMap

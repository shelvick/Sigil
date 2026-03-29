import * as THREE from "three"

const DEFAULT_CAMERA_MULTIPLIER = 1.6

export function normalizeCoordinates(systems, targetRange = 500) {
  if (!Array.isArray(systems) || systems.length === 0) {
    return {
      positions: new Float32Array(),
      offset: { x: 0, y: 0, z: 0 },
      scale: 1
    }
  }

  let minX = Number.POSITIVE_INFINITY
  let maxX = Number.NEGATIVE_INFINITY
  let minY = Number.POSITIVE_INFINITY
  let maxY = Number.NEGATIVE_INFINITY
  let minZ = Number.POSITIVE_INFINITY
  let maxZ = Number.NEGATIVE_INFINITY

  systems.forEach((system) => {
    const x = Number(system.x) || 0
    const y = Number(system.y) || 0
    const z = Number(system.z) || 0

    if (x < minX) minX = x
    if (x > maxX) maxX = x
    if (y < minY) minY = y
    if (y > maxY) maxY = y
    if (z < minZ) minZ = z
    if (z > maxZ) maxZ = z
  })

  const offset = {
    x: (minX + maxX) / 2,
    y: (minY + maxY) / 2,
    z: (minZ + maxZ) / 2
  }

  const maxRadius = systems.reduce((maxDistance, system) => {
    const xDistance = Math.abs((Number(system.x) || 0) - offset.x)
    const yDistance = Math.abs((Number(system.y) || 0) - offset.y)
    const zDistance = Math.abs((Number(system.z) || 0) - offset.z)
    const systemDistance = Math.max(xDistance, yDistance, zDistance)

    return Math.max(maxDistance, systemDistance)
  }, 0)

  const scale = maxRadius > 0 ? targetRange / maxRadius : 0
  const positions = new Float32Array(systems.length * 3)

  systems.forEach((system, index) => {
    positions[index * 3] = ((Number(system.x) || 0) - offset.x) * scale
    positions[index * 3 + 1] = ((Number(system.y) || 0) - offset.y) * scale
    positions[index * 3 + 2] = ((Number(system.z) || 0) - offset.z) * scale
  })

  return { positions, offset, scale }
}

export function normalizeWithTransform(systems, normalization) {
  if (!Array.isArray(systems) || systems.length === 0) {
    return new Float32Array()
  }

  const offset = normalization?.offset || { x: 0, y: 0, z: 0 }
  const scale = Number.isFinite(normalization?.scale) ? normalization.scale : 1
  const positions = new Float32Array(systems.length * 3)

  systems.forEach((system, index) => {
    positions[index * 3] = ((Number(system.x) || 0) - offset.x) * scale
    positions[index * 3 + 1] = ((Number(system.y) || 0) - offset.y) * scale
    positions[index * 3 + 2] = ((Number(system.z) || 0) - offset.z) * scale
  })

  return positions
}

export function buildSystemIndex(systems) {
  const index = new Map()

  systems.forEach((system, arrayIndex) => {
    index.set(system.id, arrayIndex)
  })

  return index
}

export function buildOverlayPositions(systemIds, systemIndex, positions) {
  const overlayIds = []
  const overlayPositions = []

  for (const systemId of systemIds) {
    const pointIndex = systemIndex.get(systemId)

    if (pointIndex === undefined) {
      continue
    }

    overlayIds.push(systemId)
    overlayPositions.push(
      positions[pointIndex * 3],
      positions[pointIndex * 3 + 1],
      positions[pointIndex * 3 + 2]
    )
  }

  return {
    systemIds: overlayIds,
    positions: new Float32Array(overlayPositions)
  }
}

export function resolveSystemId(intersectionIndex, systemIds) {
  if (!Number.isInteger(intersectionIndex)) {
    return null
  }

  return systemIds[intersectionIndex] ?? null
}

export function createDefaultCamera(galaxyExtent = 500) {
  const safeExtent = Math.max(Number(galaxyExtent) || 0, 1)
  const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 5_000)
  camera.position.set(0, safeExtent * DEFAULT_CAMERA_MULTIPLIER, 0)
  camera.lookAt(0, 0, 0)
  return camera
}

export function shouldShowConstellations(cameraDistance, threshold) {
  return cameraDistance > threshold
}

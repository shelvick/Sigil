const pseudonymCache = new Map()
let activeAddress = null

export function cachePseudonym(address, keypair) {
  pseudonymCache.set(address, keypair)
  return keypair
}

export function getPseudonym(address) {
  return pseudonymCache.get(address) || null
}

export function setActivePseudonym(keypair) {
  if (!keypair) {
    activeAddress = null
    return null
  }

  const address = keypair.getPublicKey().toSuiAddress()
  cachePseudonym(address, keypair)
  activeAddress = address
  return keypair
}

export function activatePseudonym(address) {
  const keypair = getPseudonym(address)
  if (!keypair) {
    return null
  }

  activeAddress = address
  return keypair
}

export function getActivePseudonym() {
  if (!activeAddress) {
    return null
  }

  return getPseudonym(activeAddress)
}

export function clearPseudonyms() {
  pseudonymCache.clear()
  activeAddress = null
}

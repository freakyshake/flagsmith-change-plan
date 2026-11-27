import flagsmith from '@flagsmith/flagsmith';

export function searchEndpoint() {
  return flagsmith.hasFeature('search_v2') ? '/api/v2/search' : '/api/search';
}

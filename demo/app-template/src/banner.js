import flagsmith from '@flagsmith/flagsmith';

export function banner() {
  return flagsmith.hasFeature('holiday_banner') ? '<div class="banner">Holiday sale!</div>' : '';
}

export function pricingHeadline() {
  return flagsmith.getValue('pricing_copy') || 'Simple pricing';
}

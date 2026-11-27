import flagsmith from '@flagsmith/flagsmith';

export function cartButtonLabel() {
  return flagsmith.hasFeature('new_checkout') ? 'Go to checkout' : 'Checkout';
}

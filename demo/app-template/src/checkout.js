import flagsmith from '@flagsmith/flagsmith';

export function renderCheckout(cart) {
  if (flagsmith.hasFeature('new_checkout')) {
    const express = flagsmith.hasFeature('express_pay');
    return `<section class="checkout-v2">${cart.total}${express ? ' · Express Pay' : ''}</section>`;
  }
  return `<section class="checkout">${cart.total}</section>`;
}

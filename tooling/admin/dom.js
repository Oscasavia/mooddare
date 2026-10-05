export const $ = id => document.getElementById(id);
export function text(tag, value, className) {
  const element = document.createElement(tag);
  element.textContent = value;
  if (className) element.className = className;
  return element;
}
export const number = value => new Intl.NumberFormat().format(value);

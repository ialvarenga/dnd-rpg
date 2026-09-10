import {validateMapSpec} from './validation.js';
import {validateCollisions} from './collision-validation.js';

export function validateFullMap(spec) {
  const schema = validateMapSpec(spec);
  return {
    errors: [...schema.errors, ...validateCollisions(spec)],
    warnings: schema.warnings,
  };
}

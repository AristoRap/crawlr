## [Unreleased]

## [0.2.3] - 2025-10-03

- Introduce custom HTTPInterface cookie_jar wrapped in concurrent map for safe reads/writes when batch visiting async
- Rubocop related updates

## [0.2.2] - 2025-10-01

- Refactor robots.rb and parser.rb to address a few rubocop complaints

## [0.2.1] - 2025-09-30

- Fix paginated_visit to properly handle provided url queries (if present)
- Update paginated_visit batch size parameter to respect max_depth (if max_depth set > 0)

## [0.2.0] - 2025-09-30

- Tidied up documentation and inline comments
- Fixed small bugs caused by typos
- Added a few examples demonstrating usage

## [0.1.0] - 2025-09-29

- Initial release

# Changelog

## [0.8.0](https://github.com/fstermann/bouncer/compare/v0.7.0...v0.8.0) (2026-11-08)


### Features

* archive meeting notes with an archived tag ([41317ee](https://github.com/fstermann/bouncer/commit/41317ee0a14d651f4235b6cfdd209f18e41a6c5a))
* chat with Claude Code from the notch with Command-Shift-C ([#41](https://github.com/fstermann/bouncer/issues/41)) ([cc03073](https://github.com/fstermann/bouncer/commit/cc030735ebd46d8bbb21cb5f60dffc794860f013))
* continue and nest Markdown lists while writing a note ([687e890](https://github.com/fstermann/bouncer/commit/687e890bf46701f3c049cb45f0578dc6403fb76a))
* dated todos, a presentation timer and tag colours in the todo file ([#40](https://github.com/fstermann/bouncer/issues/40)) ([1a6effd](https://github.com/fstermann/bouncer/commit/1a6effda32150c26480e9b377f45cc56f73f1981))
* draw the page button as a bare icon, lit on hover ([59159d3](https://github.com/fstermann/bouncer/commit/59159d33fe4ac0c1a438f4e5fbb26f0d0ccca1cf))
* give Claude its own filter chip and rework the due and tag menus ([8c9d0f9](https://github.com/fstermann/bouncer/commit/8c9d0f92d993f0082081b651b671e31e0940dc75))
* give todos a time, and remind of timed todos, meetings and Claude's answers ([e0f4481](https://github.com/fstermann/bouncer/commit/e0f4481913257bbf76eca6436c2bae9137488884))
* paste images into todos and notes, and see them on hover ([38a6258](https://github.com/fstermann/bouncer/commit/38a62580817315caf6157ae34a80e32421e4c62c))
* right-click todos, mark them in progress and send them to Claude Code ([c22ce55](https://github.com/fstermann/bouncer/commit/c22ce55da45c97b7c003c235b039fae57788d0f6))
* take meeting notes from the notch with Command-Shift-N ([#37](https://github.com/fstermann/bouncer/issues/37)) ([f294217](https://github.com/fstermann/bouncer/commit/f294217f9d419140282a0b36ae2211241c78c2e6))
* take screenshots into meeting notes ([d7c0b47](https://github.com/fstermann/bouncer/commit/d7c0b472064217e152631d4303e159e3ea964846))
* take screenshots into questions to Claude ([33f8871](https://github.com/fstermann/bouncer/commit/33f887192df7a77693a6cb86950e451f01fcdaf4))
* type -&gt; or --&gt; for an arrow in todos and notes ([27734b8](https://github.com/fstermann/bouncer/commit/27734b8a2e294f31dacc269e37d618f8de9d4742))


### Bug Fixes

* pick a note's end from the usual lengths before one is set ([761cbb4](https://github.com/fstermann/bouncer/commit/761cbb46c5f3d6067b721be8937bae914e8c251b))
* send todos again when their Claude session was never saved ([44234f8](https://github.com/fstermann/bouncer/commit/44234f8e19d3f3c6594ece36feaa5912945bee9b))


### Performance

* list and read meeting notes faster ([34dfbe6](https://github.com/fstermann/bouncer/commit/34dfbe68ed8a6173565a7f47d690a03649bac1e7))
* search todos and notes faster ([981d5c3](https://github.com/fstermann/bouncer/commit/981d5c3977f172369ba0afa227d1b518f0853253))
* sort the todo list once per redraw and read the file faster ([fee4661](https://github.com/fstermann/bouncer/commit/fee4661cdc330f0cdcc547bed99e08ca97d0e9fe))


### Documentation

* run make run without asking, ask only before make ctl ([a8feb83](https://github.com/fstermann/bouncer/commit/a8feb837cf442679a636aeab4850e7d4b5c43206))

## [0.7.0](https://github.com/fstermann/bouncer/compare/v0.6.0...v0.7.0) (2026-10-31)


### Features

* drive, photograph and record Bouncer Dev from a shell ([#36](https://github.com/fstermann/bouncer/issues/36)) ([7247278](https://github.com/fstermann/bouncer/commit/724727809929272e1dd4e2d2eb35204c2fbd3487))
* make Bouncer work on macOS 27 ([#35](https://github.com/fstermann/bouncer/issues/35)) ([683ca6e](https://github.com/fstermann/bouncer/commit/683ca6e34a4ecaf138dbcb37758e4ff3b5f9ac7e))

## [0.6.0](https://github.com/fstermann/bouncer/compare/v0.5.0...v0.6.0) (2026-10-29)


### ⚠ BREAKING CHANGES

* run menu bar items and todos as independent modes ([#34](https://github.com/fstermann/bouncer/issues/34))

### Features

* animate tag chips as they change and fade the strip's start ([a05256e](https://github.com/fstermann/bouncer/commit/a05256e94e6f25ae5744658d2959aae691576028))
* animate ticked and deleted todos out of the list ([bbeab87](https://github.com/fstermann/bouncer/commit/bbeab877ada3a37a6f5a79c9b2455ac4586b8b71))
* fade the todo list's edges as it scrolls, easing in with the distance ([7c77684](https://github.com/fstermann/bouncer/commit/7c77684efc8611f40236f893f7797132be42e341))
* give a new todo the active tag filters ([2e54bb0](https://github.com/fstermann/bouncer/commit/2e54bb0a106ea168a70b383a62f6bba9cc9f8492))
* move selected tag filters to the front and fade the overflowing strip ([7262409](https://github.com/fstermann/bouncer/commit/7262409fe33bf59adcbf3fc1349d5e936c4db98c))
* multi-tag filters, one-click todo editing and multi-line titles ([#29](https://github.com/fstermann/bouncer/issues/29)) ([248146e](https://github.com/fstermann/bouncer/commit/248146e2fe747fe1604ea4f68ceec73fde5c348b))
* narrow the offered tag filters and their counts to the selected ones ([3c44e49](https://github.com/fstermann/bouncer/commit/3c44e4977c6e20ab4d1dd8918184bc82194cdc65))
* run menu bar items and todos as independent modes ([#34](https://github.com/fstermann/bouncer/issues/34)) ([f104f10](https://github.com/fstermann/bouncer/commit/f104f10970e04e2555f6ee4f06a7fc9eedcfbf4d))
* search the todos from the tag row or with Command-F ([09b56bc](https://github.com/fstermann/bouncer/commit/09b56bc5271f3cabac24d16ff35a00ce2e643e53))
* show how many listed todos are open ([f335500](https://github.com/fstermann/bouncer/commit/f3355008e90779283f47f9e04a590f548a081038))
* show tags in the todo editor's text and complete them there ([#32](https://github.com/fstermann/bouncer/issues/32)) ([b37aa00](https://github.com/fstermann/bouncer/commit/b37aa0074990beb1214ea55dcd12d05cbe4a794b))
* spring the todo panel shorter with the rows it loses ([9693078](https://github.com/fstermann/bouncer/commit/9693078abd3087b7067211fe5dab4eaa85925052))
* tag counts, untagged filter and tags below long titles ([#31](https://github.com/fstermann/bouncer/issues/31)) ([8bccd84](https://github.com/fstermann/bouncer/commit/8bccd84e46f840a614a5c5ecec92788194784525))


### Bug Fixes

* handle cut, copy, paste and select all in the todo panel ([c0bf7cc](https://github.com/fstermann/bouncer/commit/c0bf7cca6b5dc919ee95f2428bd70a18a2a4d320))
* keep notch hover on the display it was meant for ([35fa8e9](https://github.com/fstermann/bouncer/commit/35fa8e9e4842af6c2c3798dc2806a129fc9212d9))
* reveal at a stand-in notch only from the top edge ([7734a1b](https://github.com/fstermann/bouncer/commit/7734a1b5b04867cd7dccc9907e540c9a4ac0d746))


### Documentation

* note that log show fails inside Claude Code ([98afd2a](https://github.com/fstermann/bouncer/commit/98afd2a278b215e16e0db2af7427d5b8ba4749e1))

## [0.5.0](https://github.com/fstermann/bouncer/compare/v0.4.0...v0.5.0) (2026-10-26)


### Features

* add a notch bar style that grows out of the display notch ([#21](https://github.com/fstermann/bouncer/issues/21)) ([adea201](https://github.com/fstermann/bouncer/commit/adea201b68cf2b94a2ba630066e7b20249dd88aa))
* add a todo page to the notch panel ([#22](https://github.com/fstermann/bouncer/issues/22)) ([5840a3d](https://github.com/fstermann/bouncer/commit/5840a3da734df1349b65bedfd02e4a13fa187d39))
* add row actions, tag completion and undoable delete to todos ([#25](https://github.com/fstermann/bouncer/issues/25)) ([ed9b8c2](https://github.com/fstermann/bouncer/commit/ed9b8c274e0e00c27fb8211ee0e9500ce95f32f3))
* keep todos in a local file by default ([#27](https://github.com/fstermann/bouncer/issues/27)) ([5263ec8](https://github.com/fstermann/bouncer/commit/5263ec88e796bb5283743f76414378faa0822dff))
* polish the todo page layout and add category deletion ([#26](https://github.com/fstermann/bouncer/issues/26)) ([149702e](https://github.com/fstermann/bouncer/commit/149702e58d0aaf9e4e9656982374b09118913a10))


### Bug Fixes

* use dark text on selected yellow tag chips ([#28](https://github.com/fstermann/bouncer/issues/28)) ([5426c3d](https://github.com/fstermann/bouncer/commit/5426c3dfe073834fa8052c731364ca7b04941389))


### Documentation

* add shared agent instructions ([#18](https://github.com/fstermann/bouncer/issues/18)) ([084ee69](https://github.com/fstermann/bouncer/commit/084ee69c23474599c2b2207cce9b78224f6e3992))

## [0.4.0](https://github.com/fstermann/bouncer/compare/v0.3.0...v0.4.0) (2026-08-25)


### Features

* grab and land menu bar items under the display notch ([#14](https://github.com/fstermann/bouncer/issues/14)) ([45c71f2](https://github.com/fstermann/bouncer/commit/45c71f2599d0d213f2d4681757509b78373cbdab))
* reorganise settings into a sidebar layout ([#17](https://github.com/fstermann/bouncer/issues/17)) ([3a8b506](https://github.com/fstermann/bouncer/commit/3a8b506de7c0844f0b05a51fefaae051f3077841))
* request standalone-bar permissions together and show their status ([#16](https://github.com/fstermann/bouncer/issues/16)) ([f34944e](https://github.com/fstermann/bouncer/commit/f34944ed064e2a138bc5f7feb68f1d13bc58b159))

## [0.3.0](https://github.com/fstermann/bouncer/compare/v0.2.1...v0.3.0) (2026-08-19)


### Features

* defer updates to Homebrew when installed via brew ([#12](https://github.com/fstermann/bouncer/issues/12)) ([df11740](https://github.com/fstermann/bouncer/commit/df11740b29d6cb78bd07879a7c030e9ff8c3ffa1))

## [0.2.1](https://github.com/fstermann/bouncer/compare/v0.2.0...v0.2.1) (2026-08-13)


### Bug Fixes

* give the Check for Updates menu item an icon ([#9](https://github.com/fstermann/bouncer/issues/9)) ([0a3a3ce](https://github.com/fstermann/bouncer/commit/0a3a3ce9517502e75c85e52739a78cfc912b893f))

## [0.2.0](https://github.com/fstermann/bouncer/compare/v0.1.0...v0.2.0) (2026-08-13)


### Features

* release Bouncer to other users, and update it in place ([#6](https://github.com/fstermann/bouncer/issues/6)) ([4850e7b](https://github.com/fstermann/bouncer/commit/4850e7be3672fffb9c5b4940f64a47cd9387a7dd))

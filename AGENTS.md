The project outline is in README.md. The list of open tasks is in TODO.md.

* The version control to use is 'jj'. Never use history-altering commands ('jj op
restore', 'jj undo'). Onlu use 'jj squash' when explicitly instructed by the user.

* For each non-trivial task create a new ticket markdown file in docs/tickets/ and link it from TODO.md. Make sure each ticket has enough information to enable progress in a fresh agent session. Use `topic-NNN-summary-in-few-words.md` naming. Use one-word topics. Make sure summary is 5 words or less.

* After completion of a each task, update design documentation (adding new files if appropriate) in docs/design/
and top-level README.md. Also update the ticket itself with the status, and link it from docs/CHANGES.md with date and brief summary of changes.

* Whenever the workspace compiles and tests pass, 'jj commit' with a good description of the changes.

* Whenever user input is needed, add the questions to the ticket with recommended answers, and move the pointer to the ticket to "TODO for humans" section at the top of TODO.


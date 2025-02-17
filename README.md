Purpose of this Rails app is to create an easy integration from Hack Club Airtable bases into Loops.so, our email list system.

The usage should be as follows:

1. In any Hack Club Airtable, create a new field called "Loops - juiceSignUpAt"
2. This Rails app should automatically detect that this field has been updated, and set the juiceSignUpAt field in Loops.so to the value of the "Loops - juiceSignUpAt" field in Airtable.
3. If there is an error - a field in Airtable called "Loops (Error) - juiceSignUpAt" will be set to the error message.
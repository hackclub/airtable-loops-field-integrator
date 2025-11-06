This is a project that automatically syncs fields from Airtable to Loops (Hack Club's email software). It uses a polling model and tries to intelligently decide when updates are needed and batch requests to cut down on API requests.

Currently supported:

- Select specific Airtable bases to sync
- Fields (for rows with an "Email" field):
  - `Loops - highwaySignedUpAt` will upsert the Airtable value for the row into Loops (if the Airtable field is null, it will not overwrite the Loops value)
  - `Loops - Override - highwaySignedUpAt` will copy the Airtable value for the row into Loops, overwriting any existing value in Loops
  - `Loops - Special - setFullName` - Uses AI to break a full name (including preferred name) into parts for Loops. This is a good way to get high quality names in Loops.
  - `Loops - Special - setFullAddress` - Uses AI to break a given full address into individual parts. This does not geocode. It just breaks into parts.
  - `Loops List - {Note}` - Set value to a comma separated list of mailing list IDs to add the email to. This will not re-subscribe users who have previously unsubscribed from a list.
    - Ex. Field name: `Loops List - 3 Cool Things`. Value: `cm96o4ubl02b30i1n6l1jctbb`

To-Do:

- Mailing list support
  - Subscribe to general mailing lists
  - Subscribe to default mailing list
- Re-subscribe support
- Write-back to SyncSource with status so users can see success / error
  - Maybe pull from envelopes? Show detailed errors
- Once mailing list stuff is deployed, migrate all Zapiers over and disable Zapiers
- For `LlmCache`, we probably don't need to store the full request. Hash is probably enough.
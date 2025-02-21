class LoopsSpecialSetFullNameJob < ApplicationJob
  # raw_name_text should be the full name of the person, or any other name details we have
  def perform(edit_timestamp, base_id, email, raw_name_text)
    prompt = <<~PROMPT
A user provided us with unstructured data for their first and last name. We need to break it into first_name and last_name parts to use in our email list system.

1. Break the provided info into first_name and last_name parts. The first name should be something that would fit nicely into the following template: "Hi firstName!"
2. Transform the parts into "nice" data. For example, transform "ZACH latta" into first_name: "Zach", last_name: "Latta"
3. If the user has a preferred name, use that because they are the recipient of the emails we're sending and we want to respect their preferences
4. Ensure that first_name + last_name contains the full name the user provided us (ex. some last names have multiple words in them)

User provided info:

#{raw_name_text}
PROMPT

    name_parts = AiService.prompt_structured(
      prompt,
      output: {
        first_name: :string,
        last_name: :string,
      }
    )

    LoopsUpdateFieldJob.set(priority: edit_timestamp.to_i).perform_later(base_id, email, {
      firstName: name_parts[:first_name],
      lastName: name_parts[:last_name],
    })
  end
end

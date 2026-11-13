///|
/// The JSON text read and write of the test and example suites now goes through
/// `moonjson`: a schema and an instance parsed by `@json.loads` validate exactly
/// as they did under the core reader, and a report written by `@json.dumps`
/// parses back to the same tree it was built from.
test {
  let schema = @moonschema.Schema::new(
    @json.loads("{\"type\": \"integer\", \"minimum\": 1}"),
  )
  assert_eq(schema.valid(@json.loads("5")), true)
  assert_eq(schema.valid(@json.loads("0")), false)
  let report = schema.report(
    @json.loads("0"),
    output=@moonschema.Output::Detailed,
  )
  let written = @json.dumps(report.to_json())
  assert_eq(@json.loads(written), report.to_json())
}

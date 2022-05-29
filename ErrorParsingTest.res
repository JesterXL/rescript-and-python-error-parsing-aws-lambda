open Test
open ErrorParsing
open Promise
open Assertions

let snsStub = (_, _, _) =>
    Promise.resolve(Ok("some message id"))

let decodeStub = () =>
    Ok( { "foo": "bar" } )

let eventStub = Js.Json.parseExn(`{
  "awslogs": {
    "data": "H4sIAAAAAAAAAO1VXYvbOBT9K8IU2oU4smX582kDmw6FDoVJ6MOOh0G2bhLN2HJWUjIpIf99rx1nZsps2T72ocZIsnTuuVfnHvDRa8FasYblty14hffXbDm7v54vFrOruTfxuicNBrdznjKWsjzmQYLbTbe+Mt1uiydUPFnaiLaSgjad0A0IC7Vo6l0jXGfEVvkS9v4a3LXSqt21My2vxaFffVRa6BpmbbfT7sy6cAZEi7QsYIwGEQ05vX33ebacL5Z3q1imfBXKPBQ1T2MuwizlWRxFeVSlWRIghd1VtjZq61SnP6rGgbFeces5sM67GzLM96Bdv3n0lMREUZJGcZayOMrTNI+iOGIsSWLOGVImQZLnPEuTLAh5ErCE8SQMeIJATOYUaudEizKECQqURzxPMhZMLpqO9/CDyA/5koVFhG8yzcL879JJAJFzDn4CvPI5T1M/i0Pmh2EoeVhDLsWqdPObmy83pfuk990jkLkxnSGlO5Ye9Mu+aaVXlN5wUHqTcf/6nH84OpZl6W0MrPq56AeKTaEWmwOWbo2qlV7TkEX90aQfBopn9EqoBiRxHcEeEryvA2LBOYyyZIXlSBANmCnBsIJ8jx7MQJw4EINhI2RMuQCzVzUQrGLbaYlBT8ptiCC60z47HIZUO0vqTmLkGWWhwNU/O5SdVJ38RjbCEqHJUHFBZAdWv3ekFa7eELfBQusNtKIYhROOlOcHNZASOS0dLnTZLUh7NikmN1gjXkCvsShlCesBenHmG9aEHMeZPNNKeLbfC+dlxUi9EUbU6MpRR1FVBvZK9PjpBTZ5wwoHNFkDbxm/zn4c1IrD56H6lzD2HyilfwLlep+9yX7W6PI1Bp2GeRi+imYHF61ew57hl8E7Dd5FUepHzHA7Grogv83727w/tuUvZd4+JfboS/UAtZsaoSycG/eB7oWhTthHqtEO920ndw26908z6o1tlLRRFX2w+N7DQU8fbJEV+R+viV9YrKnp1f/9T3sKFjL85bwm2ZquRuMsVf1oMfAG+mKxf5Z8UBpbq0VDR8yQ6x7tiobtyfK4iLGgu1OpvdPd6V+SXOSWOQgAAA=="
  }
}`)

// Example of what the data looks like
/*
{
    "messageType": "DATA_MESSAGE",
    "owner": "947227295406",
    "logGroup": "/aws/lambda/loanleasecalculatorapi-dev-getMinimumAndMaximumFinanceAmount",
    "logStream": "2022/03/14/[$LATEST]f5d74f1d91ac4754a1874853393b7860",
    "subscriptionFilters": [
        "test"
    ],
    "logEvents": [
        {
            "id": "36735872539779335322665442786606994876801460262461046793",
            "timestamp": 1647293496820,
            "message": "2022-03-14T21:31:36.819Z\tdeea944e-6e4b-4477-8512-111d41ce9daf\tERROR\tInvoke Error \t{\"errorType\":\"Error\",\"errorMessage\":\"{\\\"href\\\":\\\"/api/stores/pricing/123\\\",\\\"error\\\":\\\"failed to get state settings for dealer. err: failed to get lease tax rate. err: pricingService responded with a non-2xx status code. response: request body has an error: doesn't match the schema: Error at \\\\\\\"/address/state\\\\\\\": minimum string length is 2\\\\nSchema:\\\\n  {\\\\n    \\\\\\\"description\\\\\\\": \\\\\\\"2 character state abbreviation.\\\\\\\",\\\\n    \\\\\\\"example\\\\\\\": \\\\\\\"VA\\\\\\\",\\\\n    \\\\\\\"maxLength\\\\\\\": 2,\\\\n    \\\\\\\"minLength\\\\\\\": 2,\\\\n    \\\\\\\"type\\\\\\\": \\\\\\\"string\\\\\\\"\\\\n  }\\\\n\\\\nValue:\\\\n  \\\\\\\"\\\\\\\"\\\\n\\\\n\\\"}\",\"stack\":[\"Error: {\\\"href\\\":\\\"/api/stores/pricing/123\\\",\\\"error\\\":\\\"failed to get state settings for dealer. err: failed to get lease tax rate. err: pricingService responded with a non-2xx status code. response: request body has an error: doesn't match the schema: Error at \\\\\\\"/address/state\\\\\\\": minimum string length is 2\\\\nSchema:\\\\n  {\\\\n    \\\\\\\"description\\\\\\\": \\\\\\\"2 character state abbreviation.\\\\\\\",\\\\n    \\\\\\\"example\\\\\\\": \\\\\\\"VA\\\\\\\",\\\\n    \\\\\\\"maxLength\\\\\\\": 2,\\\\n    \\\\\\\"minLength\\\\\\\": 2,\\\\n    \\\\\\\"type\\\\\\\": \\\\\\\"string\\\\\\\"\\\\n  }\\\\n\\\\nValue:\\\\n  \\\\\\\"\\\\\\\"\\\\n\\\\n\\\"}\",\"    at Object.raiseError (/var/task/node_modules/@rescript/std/lib/js/js_exn.js:8:9)\",\"    at /var/task/src/GetMinimumAndMaximumFinanceAmount.js:212:31\",\"    at processTicksAndRejections (internal/process/task_queues.js:95:5)\"]}\n"
        }
    ]
}
*/

testAsync("send error to SNS", cb => {
  let _ = sendErrorToSNS(snsStub, eventStub)
  ->then(
      result => {
            stringEqual(result, "some message id")
            cb(~planned=1, ())
            resolve(result)
      }
  )
  ->catch(
      error => {
          Js.log2("send error to SNS failed:", error)
          fail(())
          reject(error)
      }
  )
})

testAsync("fail to parse AWS event body", cb => {
  let _ = sendErrorToSNS(snsStub, Js.Json.parseExn(`{"foo": "cow moo cheese 🧀"}`))
  ->then(
        _ => {
            fail(())
            cb(~planned=1, ())
            resolve(false)
      }
  )
  ->catch(
      _ => {
          pass(())
          cb(~planned=1, ())
          resolve(true)
      }
  )
})


let badEventStub = Js.Json.parseExn(`{
  "awslogs": {
    "data": "yo yooooo"
  }
}`)

testAsync("fail to parse CloudWatch message", cb => {
  let _ = sendErrorToSNS(snsStub, badEventStub)
  ->then(
        _ => {
            fail(())
            cb(~planned=1, ())
            resolve(false)
      }
  )
  ->catch(
      _ => {
          pass(())
          cb(~planned=1, ())
          resolve(true)
      }
  )
})



let publishStub = (_, _, _) =>
    resolve({ 
        ok: true, 
        result: Js.Nullable.fromOption(Some("test message id")),
        reason: Js.Nullable.fromOption(None),
        error: Js.Nullable.fromOption(None) })

testAsync("should send a basic sns message", cb => {
    let _ = publishSNS(publishStub, "stub arn", "stub subject", "stub message")
    ->then(
        result =>
            switch result {
            | Ok(_) => {
                pass(())
                cb(~planned=1, ())
                resolve(true)
            }
            | Error(_) => {
                fail(())
                cb(~planned=1, ())
                resolve(false)
            }
            }
    )
})

let publishErrorStub = (_, _, _) =>
    resolve({ 
        ok: false, 
        result: Js.Nullable.fromOption(None),
        reason: Js.Nullable.fromOption(Some("test reason")),
        error: Js.Nullable.fromOption(Some("test error")) })

testAsync("should handle a failed sns message", cb => {
    let _ = publishSNS(publishErrorStub, "stub arn", "stub subject", "stub message")
    ->then(
        result =>
            switch result {
            | Ok(_) => {
                fail(())
                cb(~planned=1, ())
                resolve(false)
            }
            | Error(_) => {
                pass(())
                cb(~planned=1, ())
                resolve(true)
            }
            }
    )
})
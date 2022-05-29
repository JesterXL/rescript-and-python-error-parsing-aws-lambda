from http import client
from pymonad.either import Left, Right
from pymonad.tools import curry
import json
import base64
import zlib
from pydash import (get)
import boto3
import os


event_stub = {
  "awslogs": {
    "data": "H4sIAAAAAAAAAO1VXYvbOBT9K8IU2oU4smX582kDmw6FDoVJ6MOOh0G2bhLN2HJWUjIpIf99rx1nZsps2T72ocZIsnTuuVfnHvDRa8FasYblty14hffXbDm7v54vFrOruTfxuicNBrdznjKWsjzmQYLbTbe+Mt1uiydUPFnaiLaSgjad0A0IC7Vo6l0jXGfEVvkS9v4a3LXSqt21My2vxaFffVRa6BpmbbfT7sy6cAZEi7QsYIwGEQ05vX33ebacL5Z3q1imfBXKPBQ1T2MuwizlWRxFeVSlWRIghd1VtjZq61SnP6rGgbFeces5sM67GzLM96Bdv3n0lMREUZJGcZayOMrTNI+iOGIsSWLOGVImQZLnPEuTLAh5ErCE8SQMeIJATOYUaudEizKECQqURzxPMhZMLpqO9/CDyA/5koVFhG8yzcL879JJAJFzDn4CvPI5T1M/i0Pmh2EoeVhDLsWqdPObmy83pfuk990jkLkxnSGlO5Ye9Mu+aaVXlN5wUHqTcf/6nH84OpZl6W0MrPq56AeKTaEWmwOWbo2qlV7TkEX90aQfBopn9EqoBiRxHcEeEryvA2LBOYyyZIXlSBANmCnBsIJ8jx7MQJw4EINhI2RMuQCzVzUQrGLbaYlBT8ptiCC60z47HIZUO0vqTmLkGWWhwNU/O5SdVJ38RjbCEqHJUHFBZAdWv3ekFa7eELfBQusNtKIYhROOlOcHNZASOS0dLnTZLUh7NikmN1gjXkCvsShlCesBenHmG9aEHMeZPNNKeLbfC+dlxUi9EUbU6MpRR1FVBvZK9PjpBTZ5wwoHNFkDbxm/zn4c1IrD56H6lzD2HyilfwLlep+9yX7W6PI1Bp2GeRi+imYHF61ew57hl8E7Dd5FUepHzHA7Grogv83727w/tuUvZd4+JfboS/UAtZsaoSycG/eB7oWhTthHqtEO920ndw26908z6o1tlLRRFX2w+N7DQU8fbJEV+R+viV9YrKnp1f/9T3sKFjL85bwm2ZquRuMsVf1oMfAG+mKxf5Z8UBpbq0VDR8yQ6x7tiobtyfK4iLGgu1OpvdPd6V+SXOSWOQgAAA=="
  }
}

def decode_event(event):
    try:
        result = base64.b64decode(get(event, "awslogs.data"))
        return Right(result)
    except Exception as e:
        return Left(e)

def unzip_logs(event):
    try:
        result = zlib.decompress(event, 16+zlib.MAX_WBITS)
        return Right(result)
    except Exception as e:
        return Left(e)

def parse_log_messages(decompressed_data):
    try:
        data = json.loads(decompressed_data)
        fixed = list(map(fix_json_log_message, data["logEvents"]))
        parsed = list(map(parse_json_log_message, fixed))
        return Right({**data, 'logEvents': parsed})
    except Exception as e:
        return Left(e)

def fix_json_log_message(log_message):
    msg = log_message["message"]
    index_of_slash = msg.index("{")
    return msg[index_of_slash:len(msg)]

def parse_json_log_message(log_message):
    return json.loads(log_message)

def format_message_for_sns(cloud_watch_log):
    lambda_name = get(cloud_watch_log['logGroup'].split('/'), '[3]', 'Unknown Lambda name.')
    sns_message_were_sending = {
        'lambdaName': lambda_name,
        'logGroup': cloud_watch_log['logGroup'],
        'logStream': cloud_watch_log['logStream'],
        'messages': cloud_watch_log['logEvents']
    }
    return Right((f'Lambda Error for {lambda_name}', sns_message_were_sending))

@curry(3)
def publish(sns, arn, subject_and_message):
    try:
        subject, message = subject_and_message
        response = sns.publish(
            TopicArn=arn,
            Message=json.dumps(message),
            Subject=subject,
        )
        return Right(
            get(response, 'messageID', 'unknown message ID')
        )
    except Exception as e:
        return Left(e)

def get_arn_from_environment():
    env = os.environ.get('PY_ENV')
    if env == 'qa':
        return Right('arn:aws:sns:us-east-1:123123123123:app-dev-alerts-alarm')
    elif env == 'stage':
        return Right('arn:aws:sns:us-east-1:123123123123:app-stage-alerts-alarm')
    elif env == 'prod':
        return Right('arn:aws:sns:us-east-1:123123123123:app-prod-alerts-alarm')
    else:
        return Left(f'Unknown environment: {env}')

@curry(2)
def send_error_to_sns(sns, event):
    return (
        decode_event(event)
        .then(unzip_logs)
        .then(parse_log_messages)
        .then(format_message_for_sns)
        .then(publish(sns, get_arn_from_environment()))
        .either(raise_error, identity)
    )

send_error_to_sns_partial = send_error_to_sns(boto3.client('sns'))

# AWS Lambda contract requires value or
# an Exception (SQS, Step Function, etc).
# Use pure functions for all code, then
# handle the imperative side effects and
# errors in your lambda handler
def handler(event, _):
    return send_error_to_sns_partial(event)

def identity(arg):
    return arg

def raise_error(reason):
    raise Exception(reason)


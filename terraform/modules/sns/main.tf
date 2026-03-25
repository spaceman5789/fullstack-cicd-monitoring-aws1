# ── SNS Topic ────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  tags = { Name = "${var.project_name}-${var.environment}-alerts" }
}

# ── Email Subscription ──────────────────────────────────────────
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Slack Subscription (via Lambda) ──────────────────────────────
resource "aws_iam_role" "slack_lambda" {
  count       = var.slack_webhook_url != "" ? 1 : 0
  name_prefix = "${var.project_name}-slack-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "slack_lambda_logs" {
  count      = var.slack_webhook_url != "" ? 1 : 0
  role       = aws_iam_role.slack_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "slack_lambda" {
  count       = var.slack_webhook_url != "" ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/slack_notifier.zip"

  source {
    content  = <<-PYTHON
import json, os, urllib.request

SLACK_WEBHOOK = os.environ["SLACK_WEBHOOK_URL"]

def handler(event, context):
    message = event["Records"][0]["Sns"]["Message"]
    try:
        alarm = json.loads(message)
        text = f":rotating_light: *{alarm['AlarmName']}*\n{alarm['AlarmDescription']}\nState: {alarm['NewStateValue']}\nRegion: {alarm['Region']}"
    except (json.JSONDecodeError, KeyError):
        text = message

    payload = json.dumps({"text": text}).encode()
    req = urllib.request.Request(SLACK_WEBHOOK, data=payload, headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req)
    return {"statusCode": 200}
PYTHON
    filename = "index.py"
  }
}

resource "aws_lambda_function" "slack_notifier" {
  count            = var.slack_webhook_url != "" ? 1 : 0
  function_name    = "${var.project_name}-${var.environment}-slack-notifier"
  role             = aws_iam_role.slack_lambda[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.slack_lambda[0].output_path
  source_code_hash = data.archive_file.slack_lambda[0].output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }
}

resource "aws_lambda_permission" "sns" {
  count         = var.slack_webhook_url != "" ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "slack" {
  count     = var.slack_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier[0].arn
}

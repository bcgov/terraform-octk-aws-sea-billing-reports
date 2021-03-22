

help:
	@echo "---------------HELP-----------------"
	@echo "To build the lambda type make build_lambda"	
	@echo "To deploy the project type make deploy"
	@echo "To destroy the project type make destory"
	@echo "------------------------------------"


build_lambda:
	@echo "Packaging process-cur"
	@cd lambda/process-cur && zip -r ../dist/lambda_process_cur.zip .

	@echo "Packaging process-cur-reports"
	@cd lambda/process-cur-reports && zip -r ../dist/lambda_process_cur_reports.zip .

	@echo "Packaging process-cur-cleanup"
	@cd lambda/process-cur-cleanup && zip -r ../dist/lambda_process_cur_cleanup.zip .

	@echo "Packaging process-layer"
	@cd lambda/process-cur-layer &&	./build.sh

	@echo "Building Lambda Done"

deploy:
	@echo "Deploying solution..."
	@terraform init terraform/aws
	@terraform apply terraform/aws
	@echo "Deploying solution...Done"


destroy:
	@echo "Destroying solution..."
	@terraform init terraform/aws
	@terraform destroy terraform/aws
	@echo "Destroying solution...Done"

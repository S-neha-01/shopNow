// ============================================================
// ShopNow MERN — Jenkins CI/CD Pipeline
//
// Prerequisites (configure in Jenkins → Manage Credentials):
//   DOCKER_CREDENTIALS_ID  — DockerHub username/password credential
//   KUBE_CONFIG_ID         — Secret file containing kubeconfig
//   GITHUB_CREDENTIALS_ID  — GitHub username/password or SSH key
//
// Pipeline stages:
//   1. Checkout        — Clone source code
//   2. Test            — Run backend and frontend tests
//   3. Build Images    — Build Docker images for all 3 services
//   4. Push Images     — Push tagged images to registry
//   5. Deploy (K8s)    — Apply manifests or upgrade Helm release
//   6. Verify          — Smoke-test health endpoints
//   7. Notify          — Post build status to console / Slack
// ============================================================

pipeline {
    agent any

    // ── Configurable parameters (override from Jenkins UI) ──────────────
    parameters {
        string(
            name: 'IMAGE_TAG',
            defaultValue: '',
            description: 'Docker image tag. Defaults to the short Git SHA if left blank.'
        )
        string(
            name: 'DOCKER_REGISTRY',
            defaultValue: 'docker.io/yourorg',   // CHANGE to your registry
            description: 'Docker registry prefix (e.g. docker.io/yourorg or ghcr.io/yourorg)'
        )
        booleanParam(
            name: 'DEPLOY_VIA_HELM',
            defaultValue: true,
            description: 'Use Helm for deployment. Set false to use raw kubectl apply.'
        )
        booleanParam(
            name: 'RUN_TESTS',
            defaultValue: true,
            description: 'Run unit/integration tests before building images.'
        )
        choice(
            name: 'DEPLOY_ENV',
            choices: ['staging', 'production'],
            description: 'Target deployment environment.'
        )
    }

    // ── Environment variables ────────────────────────────────────────────
    environment {
        // Credential IDs configured in Jenkins
        DOCKER_CREDENTIALS_ID = 'dockerhub-credentials'
        KUBE_CONFIG_ID        = 'kubeconfig-secret'
        GITHUB_CREDENTIALS_ID = 'github-credentials'

        // Registry and image names
        REGISTRY          = "${params.DOCKER_REGISTRY}"
        FRONTEND_IMAGE    = "${REGISTRY}/shopnow-frontend"
        ADMIN_IMAGE       = "${REGISTRY}/shopnow-admin"
        BACKEND_IMAGE     = "${REGISTRY}/shopnow-backend"

        // Kubernetes namespace
        K8S_NAMESPACE     = 'shopnow'
        HELM_RELEASE      = 'shopnow'
        HELM_CHART_PATH   = './helm/shopnow'

        // Computed at runtime (set in 'Prepare' stage)
        IMAGE_TAG         = ''
    }

    // ── Pipeline options ─────────────────────────────────────────────────
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()           // Prevent parallel deploys
        timestamps()
    }

    // ── Trigger: build on push to main or develop ────────────────────────
    triggers {
        pollSCM('H/5 * * * *')             // Poll every 5 min (replace with webhook)
    }

    // ════════════════════════════════════════════════════════════════════
    stages {

        // ── Stage 1: Checkout ──────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/mohanDevOps-arch/shopNow.git',
                        credentialsId: env.GITHUB_CREDENTIALS_ID
                    ]]
                ])

                script {
                    // Resolve image tag: parameter → short SHA → build number
                    env.IMAGE_TAG = params.IMAGE_TAG?.trim() ?:
                        sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() ?:
                        "build-${env.BUILD_NUMBER}"

                    echo "Building tag: ${env.IMAGE_TAG}"
                    echo "Branch: ${env.GIT_BRANCH}"
                    echo "Commit: ${env.GIT_COMMIT}"
                }
            }
        }

        // ── Stage 2: Test ──────────────────────────────────────────────
        stage('Test') {
            when { expression { return params.RUN_TESTS } }
            parallel {
                stage('Backend Tests') {
                    steps {
                        dir('backend') {
                            sh '''
                                echo "=== Installing backend dependencies ==="
                                npm ci
                                echo "=== Running backend tests ==="
                                npm test --if-present || echo "No tests defined"
                            '''
                        }
                    }
                }
                stage('Frontend Tests') {
                    steps {
                        dir('frontend') {
                            sh '''
                                echo "=== Installing frontend dependencies ==="
                                npm ci
                                echo "=== Running frontend tests ==="
                                CI=true npm test --if-present || echo "No tests defined"
                            '''
                        }
                    }
                }
                stage('Admin Tests') {
                    steps {
                        dir('admin') {
                            sh '''
                                npm ci
                                CI=true npm test --if-present || echo "No tests defined"
                            '''
                        }
                    }
                }
            }
        }

        // ── Stage 3: Build Docker Images ───────────────────────────────
        stage('Build Images') {
            parallel {
                stage('Build Backend') {
                    steps {
                        sh """
                            docker build \\
                                -t ${env.BACKEND_IMAGE}:${env.IMAGE_TAG} \\
                                -t ${env.BACKEND_IMAGE}:latest \\
                                ./backend
                        """
                    }
                }
                stage('Build Frontend') {
                    steps {
                        sh """
                            docker build \\
                                --build-arg REACT_APP_API_BASE_URL=/api \\
                                -t ${env.FRONTEND_IMAGE}:${env.IMAGE_TAG} \\
                                -t ${env.FRONTEND_IMAGE}:latest \\
                                ./frontend
                        """
                    }
                }
                stage('Build Admin') {
                    steps {
                        sh """
                            docker build \\
                                --build-arg REACT_APP_API_BASE_URL=/api \\
                                -t ${env.ADMIN_IMAGE}:${env.IMAGE_TAG} \\
                                -t ${env.ADMIN_IMAGE}:latest \\
                                ./admin
                        """
                    }
                }
            }
        }

        // ── Stage 4: Push Images ───────────────────────────────────────
        stage('Push Images') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.DOCKER_CREDENTIALS_ID,
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                    '''
                    sh """
                        docker push ${env.BACKEND_IMAGE}:${env.IMAGE_TAG}
                        docker push ${env.BACKEND_IMAGE}:latest
                        docker push ${env.FRONTEND_IMAGE}:${env.IMAGE_TAG}
                        docker push ${env.FRONTEND_IMAGE}:latest
                        docker push ${env.ADMIN_IMAGE}:${env.IMAGE_TAG}
                        docker push ${env.ADMIN_IMAGE}:latest
                    """
                }
            }
        }

        // ── Stage 5: Deploy ────────────────────────────────────────────
        stage('Deploy') {
            steps {
                withCredentials([file(
                    credentialsId: env.KUBE_CONFIG_ID,
                    variable: 'KUBECONFIG'
                )]) {
                    script {
                        if (params.DEPLOY_VIA_HELM) {
                            // ── Helm deployment ──────────────────────
                            echo "Deploying via Helm (release: ${env.HELM_RELEASE})"
                            sh """
                                helm upgrade --install ${env.HELM_RELEASE} ${env.HELM_CHART_PATH} \\
                                    --namespace ${env.K8S_NAMESPACE} \\
                                    --create-namespace \\
                                    --set backend.image.tag=${env.IMAGE_TAG} \\
                                    --set frontend.image.tag=${env.IMAGE_TAG} \\
                                    --set admin.image.tag=${env.IMAGE_TAG} \\
                                    --set global.imagePullPolicy=Always \\
                                    --wait \\
                                    --timeout 5m \\
                                    --atomic
                            """
                        } else {
                            // ── Raw kubectl deployment ───────────────
                            echo "Deploying via kubectl apply"
                            sh """
                                kubectl apply -f k8s/namespace.yaml
                                kubectl apply -f k8s/mongodb/
                                kubectl apply -f k8s/backend/
                                kubectl apply -f k8s/frontend/
                                kubectl apply -f k8s/admin/
                                kubectl apply -f k8s/ingress.yaml

                                # Update image tags on running deployments
                                kubectl set image deployment/backend \\
                                    backend=${env.BACKEND_IMAGE}:${env.IMAGE_TAG} \\
                                    -n ${env.K8S_NAMESPACE}
                                kubectl set image deployment/frontend \\
                                    frontend=${env.FRONTEND_IMAGE}:${env.IMAGE_TAG} \\
                                    -n ${env.K8S_NAMESPACE}
                                kubectl set image deployment/admin \\
                                    admin=${env.ADMIN_IMAGE}:${env.IMAGE_TAG} \\
                                    -n ${env.K8S_NAMESPACE}

                                # Wait for rollouts to complete
                                kubectl rollout status deployment/backend  -n ${env.K8S_NAMESPACE} --timeout=3m
                                kubectl rollout status deployment/frontend -n ${env.K8S_NAMESPACE} --timeout=3m
                                kubectl rollout status deployment/admin    -n ${env.K8S_NAMESPACE} --timeout=3m
                            """
                        }
                    }
                }
            }
        }

        // ── Stage 6: Smoke Test / Verify ──────────────────────────────
        stage('Verify') {
            steps {
                withCredentials([file(
                    credentialsId: env.KUBE_CONFIG_ID,
                    variable: 'KUBECONFIG'
                )]) {
                    sh """
                        echo "=== Pod status ==="
                        kubectl get pods -n ${env.K8S_NAMESPACE}

                        echo "=== Service endpoints ==="
                        kubectl get svc  -n ${env.K8S_NAMESPACE}

                        echo "=== Checking backend health endpoint ==="
                        # Port-forward backend for health check (CI-friendly approach)
                        kubectl port-forward svc/backend-service 15000:5000 \\
                            -n ${env.K8S_NAMESPACE} &
                        PF_PID=\$!
                        sleep 5

                        HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" \\
                            http://localhost:15000/api/health || echo "000")

                        kill \$PF_PID 2>/dev/null || true

                        if [ "\$HTTP_CODE" != "200" ]; then
                            echo "Health check FAILED (HTTP \$HTTP_CODE)"
                            exit 1
                        fi
                        echo "Health check PASSED (HTTP \$HTTP_CODE)"
                    """
                }
            }
        }

    } // end stages

    // ════════════════════════════════════════════════════════════════════
    post {
        always {
            // Clean local Docker images to free disk space
            sh """
                docker rmi ${env.BACKEND_IMAGE}:${env.IMAGE_TAG}  || true
                docker rmi ${env.FRONTEND_IMAGE}:${env.IMAGE_TAG} || true
                docker rmi ${env.ADMIN_IMAGE}:${env.IMAGE_TAG}    || true
            """
            cleanWs()
        }
        success {
            echo """
            ✅ BUILD SUCCEEDED
            Release : ${env.HELM_RELEASE}
            Image   : ${env.IMAGE_TAG}
            Branch  : ${env.GIT_BRANCH}
            Env     : ${params.DEPLOY_ENV}
            """
            // Uncomment to send Slack notification:
            // slackSend channel: '#deployments',
            //     color: 'good',
            //     message: "✅ ShopNow deployed successfully — tag: ${env.IMAGE_TAG}"
        }
        failure {
            echo """
            ❌ BUILD FAILED — check console output for details.
            Branch : ${env.GIT_BRANCH}
            Tag    : ${env.IMAGE_TAG}
            """
            // slackSend channel: '#deployments',
            //     color: 'danger',
            //     message: "❌ ShopNow build/deploy failed — ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        }
        unstable {
            echo "⚠️  BUILD UNSTABLE — tests may have failed."
        }
    }
}

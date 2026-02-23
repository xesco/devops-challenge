# DevOps Challenge

We're excited to see you in action! This is your time to show off your technical
skills and aptitude. We want to understand how you think, how you solve problems,
and how you apply DevOps principles to real-world scenarios.

This exercise uses a simple Next.js application, but our focus is on your DevOps
expertise - working with Containers, CI/CD, and Infrastructure as Code (IaC).

Relax and enjoy the process. We know live coding can be stressful. We're more
interested in your decision-making and approach than a perfect, finished product
in the first few minutes. Please think aloud and walk us through your thought
process.

---

## Goal

Deploy the provided Next.js application in a production-ready manner.

---

## Requirements

You should be comfortable with:

- **Docker:** Building and running containers.
- **CI/CD & IaC:** Tools like GitHub Actions, Terraform, etc.
- **Orchestration:** Kubernetes, ECS, Cloud Run, or similar.
- **Git:** Version control.

---

## Tasks

### Task 1: Containerize the Application

- Write a Dockerfile to containerize the application.
- Ensure it follows best practices for a Next.js application.
- Build and run the container locally to verify it works.

### Task 2: Deploy the Application

Deploy the application. We strongly prefer deploying to Kubernetes (local or
cloud), but we are open to other cloud-based solutions (Cloudflare, AWS ECS,
GCP Cloud Run, Fly.io, etc.) if that's what you're most comfortable with.

Ensure the solution is as close to production-ready as possible. Consider
aspects like:

- Security
- Scalability
- Reliability

Demonstrate that the application is reachable and returns the Latest
CryptoPrices.

---

## Time & Expectations

You have 60 minutes for this live session.

However, if you feel you cannot complete a solution you are proud of in this
time, you are welcome to treat this as a take-home assignment. You can finish it
on your own time and submit it later. We want to see your best work!

Good luck!

---

## Hints if you get stuck

**Next.js Standalone:** Next.js requires `output: "standalone"` in the
`next.config.ts` file to work properly with most container examples you'll find
online.

```ts
const nextConfig: NextConfig = {
  output: "standalone",
};
```

**Dynamic Routing:** To avoid database connections during build time (useful for
this challenge), dynamic rendering is enabled in `app/page.tsx`:

```ts
export const dynamic = "force-dynamic";
```

Maybe you don't need to set the full database url in the dockerfile.

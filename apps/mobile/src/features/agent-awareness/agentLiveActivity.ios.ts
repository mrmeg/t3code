import AgentActivity, { AgentActivityWidget, type AgentActivityProps } from "../../widgets/AgentActivity";

export function getAgentLiveActivities() {
  return AgentActivity.getInstances();
}

export function startAgentLiveActivity(props: AgentActivityProps) {
  return AgentActivity.start(props);
}

export function updateAgentActivityWidgetSnapshot(props: AgentActivityProps) {
  AgentActivityWidget.updateSnapshot(props);
}

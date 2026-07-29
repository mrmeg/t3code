import AgentActivity, { AgentActivityWidget, type AgentActivityProps } from "../../widgets/AgentActivity";

export function getAgentLiveActivities() {
  return AgentActivity.getInstances();
}

export function startAgentLiveActivity(props: AgentActivityProps, staleDate?: Date) {
  return AgentActivity.start(props, undefined, staleDate);
}

export function updateAgentActivityWidgetSnapshot(props: AgentActivityProps) {
  AgentActivityWidget.updateSnapshot(props);
}

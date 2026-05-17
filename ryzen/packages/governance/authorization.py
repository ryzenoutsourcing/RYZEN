from typing import Dict, List, Set, Any
import logging

logger = logging.getLogger(__name__)

class ActionAuthorizer:
    """
    Brain-level and Role-based authorization matrix enforcement.
    """

    # Authorized actions by brain role
    ROLE_PERMISSIONS: Dict[str, Set[str]] = {
        "orchestration": {
            "create_booking", "update_booking", "request_schedule",
            "assign_driver", "allocate_vehicle", "trigger_notification",
            "schedule_booking", "default", "validate_request", "update_history",
            "Validate Request", "default_execution", "Default Execution"
        },
        "execution": {
            "check_availability", "execute_booking", "update_schedule", "create_event",
            "check_availability", "execute_booking", "operate",
            "Check Availability", "Execute Booking"
        },
        "growth": {
            "create_booking", "generate_pricing", "update_customer", "update_history",
            "generate_pricing", "sell",
            "Generate Pricing"
        },
        "retention": {
            "validate_continuity", "update_customer", "retrieve_history",
            "validate_continuity",
            "Validate Continuity"
        },
        "intelligence": {
            "retrieve_history", "analyze_data", "generate_insights"
        },
        "test": {
            "run_test", "do_test", "bad_action", "verify_contract"
        },
        "alignment": {
            "validate_action", "perform_audit", "request_approval"
        },
        "preservation": {
            "store_memory", "retrieve_memory", "federate_memory"
        }
    }

    # Actions forbidden for all AI brains (Reserved for Human/System)
    SYSTEM_RESERVED: Set[str] = {
        "bypass_verification", "mutate_governance_memory", "override_human_approval",
        "self_modify_cognition", "disable_governance", "purge_audit_trail"
    }

    def validate(self, actor_role: str, action_type: str) -> Dict[str, Any]:
        """
        Validates if the actor is authorized to perform the action.
        """
        logger.info(f"Authorizing action: {action_type} for role: {actor_role}")

        # 1. System Reserved check
        if action_type in self.SYSTEM_RESERVED:
            return {"authorized": False, "reason": f"Action '{action_type}' is reserved for System/Human only"}

        # 2. Role-based check
        allowed_actions = self.ROLE_PERMISSIONS.get(actor_role, set())
        if action_type not in allowed_actions:
            return {"authorized": False, "reason": f"Role '{actor_role}' is not authorized to perform '{action_type}'"}

        return {"authorized": True, "reason": "Authorization granted"}

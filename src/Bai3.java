public class Bai3 {

    static void main(String[] args) {
        ListNode list1 = new ListNode(1, new ListNode(2, new ListNode(4)));

        ListNode list2 = new ListNode(1, new ListNode(3, new ListNode(4)));

        printList(mergeTwoLists(list1, list2));
    }

    public static class ListNode {
        int val;
        ListNode next;

        ListNode() {
        }

        ListNode(int val) {
            this.val = val;
        }

        ListNode(int val, ListNode next) {
            this.val = val;
            this.next = next;
        }
    }

    public static void printList(ListNode head) {
        ListNode current = head;
        while (current != null) {
            System.out.print(current.val + " -> ");
            current = current.next;
        }
    }

    public static ListNode mergeTwoLists (ListNode list1, ListNode list2) {
        if (list1 == null && list2 == null) {
            return null;
        }

        // Loop through 2 arrays
        ListNode mergedHead = new ListNode();
        ListNode mergedHeadCurrent = mergedHead;

        while (list1 != null || list2 != null) {

            if (list2 == null || (list1 != null && list1.val <= list2.val)) {
                mergedHeadCurrent.next = list1;
                mergedHeadCurrent = mergedHeadCurrent.next;
                list1 = list1.next;
            } else if (list1 == null || (list1 != null && list2 != null && list1.val > list2.val)){
                mergedHeadCurrent.next = list2;
                mergedHeadCurrent = mergedHeadCurrent.next;
                list2 = list2.next;
            }

        }

        return mergedHead.next;
    }
}
